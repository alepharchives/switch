-module(group_switch).

-export([start/1
         , init/1
         , loop/3
	 , connect/3
	 , create_subscriber/1
	 , disconnect/3
	 , offhook/2
	 , onhook/2
	 , status/1
	 , start_tone/3
	 , stop_tone/2
        ]).

-import(switch, [to_binary/1]).

-define(onhook,  "onhook").
-define(offhook, "offhook").

-define(no_tone, "").
-define(dialtone,    "dialtone").
-define(busytone,    "busytone").
-define(ringtone,    "ringtone").
-define(ringsignal,  "ringsignal").

-define(not_connected, "").

-record(s ,{% ubscriber
	  ano          = "",              % "<Ano>"
	  status       = ?onhook,         % ?onhook | ?offhook
	  tone         = ?no_tone,        % ?dialtone | ?busytone | ?ringtone
	  connected_to = ?not_connected   % ?not_connected | "<Bno>"
	 }).
	
	
%% ---
%% API
%% ---

create_subscriber(Switch) ->
    call(Switch, create_subscriber).

status(Switch) ->
    call(Switch, status).

start_tone(Switch, Ano, Tone) when is_list(Ano) andalso is_list(Tone) ->
    call(Switch, {start_tone, Ano, Tone}).

stop_tone(Switch, Ano) when is_list(Ano) ->
    start_tone(Switch, Ano, ?no_tone).

onhook(Switch, Ano) when is_list(Ano) ->
    call(Switch, {set_status, Ano, ?onhook}).

offhook(Switch, Ano) when is_list(Ano) ->
    call(Switch, {set_status, Ano, ?offhook}).

connect(Switch, Ano, Bno) when is_list(Ano) andalso is_list(Bno) ->
    call(Switch, {connect, Ano, Bno}).

disconnect(Switch, Ano, Bno) when is_list(Ano) andalso is_list(Bno) ->
    call(Switch, {disconnect, Ano, Bno}).


call(Switch, Msg) when is_list(Switch) ->
    call(list_to_atom(Switch), Msg);
call(Switch, Msg) ->
    Switch ! {self(), Msg},
    receive 
	{Switch, Answer} -> Answer

    after 3000 ->
	    {error, timeout}
    end.


%% ------
%% Server
%% ------

start(Name) when is_list(Name) ->
    start(list_to_atom(Name));
start(Name) when is_atom(Name) ->
    spawn(?MODULE, init, [Name]).

init(Name) ->
    true = register(Name, self()),
    NextAno = 1234,
    Subscribers = [],
    loop(Name, NextAno, Subscribers).

loop(Name, NextAno, Subscribers) ->
    receive
        stop -> 
	    exit(normal);

	{Who, create_subscriber} when is_pid(Who) ->
	    Who ! {Name, {ok, NextAno}},
	    ?MODULE:loop(Name, NextAno + 1, 
			 add(#s{ano = integer_to_list(NextAno)}, 
			     Subscribers));

	{Who, status} when is_pid(Who) ->
	    Who ! {Name, {ok, to_binary(format_status(Subscribers))}},
	    ?MODULE:loop(Name, NextAno, Subscribers);

	{Who, {connect, Ano, Bno}} when is_pid(Who) ->
	    try 
		NewSubscribers = do_connect(Ano, Bno, Subscribers),
		Who ! {Name, ok},
		?MODULE:loop(Name, NextAno, NewSubscribers)
	    catch
		throw:Emsg ->
		Who ! {Name, {error, Emsg}},
		?MODULE:loop(Name, NextAno, Subscribers)
	    end;

	{Who, {disconnect, Ano, Bno}} when is_pid(Who) ->
	    try 
		NewSubscribers = do_disconnect(Ano, Bno, Subscribers),
		Who ! {Name, ok},
		?MODULE:loop(Name, NextAno, NewSubscribers)
	    catch
		throw:Emsg ->
		Who ! {Name, {error, Emsg}},
		?MODULE:loop(Name, NextAno, Subscribers)
	    end;


	{Who, {set_status, Ano, Status}} when is_pid(Who) ->
	    try 
		NewSubscribers = set_status(Ano, Status, Subscribers),
		Who ! {Name, ok},
		?MODULE:loop(Name, NextAno, NewSubscribers)
	    catch
		throw:Emsg ->
		Who ! {Name, {error, Emsg}},
		?MODULE:loop(Name, NextAno, Subscribers)
	    end;


	{Who, {start_tone, Ano, Tone}} when is_pid(Who) ->
	    try 
		NewSubscribers = set_tone(Ano, Tone, Subscribers),
		Who ! {Name, ok},
		?MODULE:loop(Name, NextAno, NewSubscribers)
	    catch
		throw:Emsg ->
		Who ! {Name, {error, Emsg}},
		?MODULE:loop(Name, NextAno, Subscribers)
	    end;

        _    -> 
	    ?MODULE:loop(Name, NextAno, Subscribers)
    end.

%% -------
%% Helpers
%% -------
-define(TAB, "\t\t").

format_status(Subscribers) ->
    [["Ano",?TAB,"Status",?TAB,"Tone",?TAB,"ConnectedTo\n"]|
     [[S#s.ano,?TAB,S#s.status,?TAB,S#s.tone,?TAB,S#s.connected_to,?TAB,"\n"]
      || S <- Subscribers]].


add(S, Subscribers) ->     
    lists:keysort(#s.ano, [S|Subscribers]).

%% 
%% ( D I S ) C O N N E C T
%%
do_connect(Ano, Bno, Subscribers) ->
    %% assert that none of the subscribers already is connected
    [true,true] =
	[true || #s{ano = No, connected_to = C} <- Subscribers,
		 (Ano == No orelse Bno == No),
		 C == ?not_connected],
    
    F = fun(#s{ano = X} = S) when X == Ano -> S#s{connected_to = Bno};
	   (#s{ano = X} = S) when X == Bno -> S#s{connected_to = Ano};
	   (Subscriber)                    -> Subscriber
	end,
    lists:map(F, Subscribers).

do_disconnect(Ano, Bno, Subscribers) ->
    %% assert that the subscribers are connected
    [true,true] =
	[true || #s{ano = No, connected_to = C} <- Subscribers,
		 ((Ano == No andalso Bno == C) orelse
		  (Bno == No andalso Ano == C))],
    
    F = fun(#s{ano = X} = S) when X == Ano orelse X == Bno -> 
		S#s{connected_to = ?not_connected};
	   (Subscriber) -> 
		Subscriber
	end,
    lists:map(F, Subscribers).
		 
%%
%% S E T   S T A T U S
%%

%% Unchanged status!
set_status(Ano, Status, [#s{ano = Ano} = S | Subscribers]) ->
    [S#s{status = Status} | Subscribers];

%% Find matching Ano
set_status(Ano, Status, [S|Subscribers]) ->
    [S | set_status(Ano, Status, Subscribers)];

%% No Ano found!
set_status(_Ano, _Status, []) ->
    throw(<<"no Ano found">>).


%%
%% S E T   T O N E
%%

%% Turn off any tone
set_tone(Ano, ?no_tone, [#s{ano = Ano} = S | Subscribers]) ->
    [S#s{tone = ?no_tone} | Subscribers];

%% Set tone iff no-tone
set_tone(Ano, Tone, [#s{ano = Ano, tone = ?no_tone} = S | Subscribers]) ->
    [S#s{tone = Tone} | Subscribers];

%% Tone already set?
set_tone(Ano, Tone, [#s{ano = Ano, tone = Tone}|_] = Subscribers) ->
    Subscribers;

%% Another tone already in use?
set_tone(Ano, Tone, [#s{ano = Ano, tone = Tone2}|_]) when Tone =/= Tone2 ->
    throw(<<"tone generator already in use">>);

%% Find matching Ano
set_tone(Ano, Tone, [S|Subscribers]) ->
    [S | set_tone(Ano, Tone, Subscribers)];

%% No Ano found!
set_tone(_Ano, _Tone, []) ->
    throw(<<"no Ano found">>).


    
