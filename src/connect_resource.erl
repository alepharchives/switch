%% @author Torbjorn Tornkvist <tobbe@tornkvist.org>
%% @copyright 2011 Torbjorn Tornkvist
%% @doc A simple phone switch simulator.

-module(connect_resource).
-export([init/1
         , allowed_methods/2
         , content_types_accepted/2
         , content_types_provided/2
         , delete_resource/2
         , malformed_request/2
         , resource_exists/2
         , to_text/2
        ]).

-import(switch, [to_binary/1]).

-include_lib("webmachine/include/webmachine.hrl").

-record(ctx, {
	  ano,
	  bno,
          method,
          switch
         }).
          

init([]) ->
    {ok, #ctx{}}.
%%    {{trace, "/tmp"}, #ctx{}}. % when debugging!

%%
allowed_methods(ReqData, State) ->
    {['PUT','DELETE'], ReqData, State#ctx{method = wrq:method(ReqData)}}.

%%
content_types_accepted(ReqData, State) ->
      {[{"text/plain", to_text}], ReqData, State}.

%%
content_types_provided(ReqData, State) ->
      {[{"text/plain", to_text}], ReqData, State}.

%%
to_text(ReqData, #ctx{method = 'PUT', ano = Ano, bno = Bno,
		      switch = SwitchName} = State) ->
    Path = "/x/"++SwitchName++"/"++Ano++"/connect/"++Bno,
    {{halt,201},
     wrq:set_resp_header("Location", Path, ReqData),
     State}.

%%
resource_exists(ReqData, #ctx{method = 'PUT', ano = Ano, bno = Bno,
			      switch = SwitchName} = State) ->
    case group_switch:connect(SwitchName, Ano, Bno) of
	ok ->
	    {true, ReqData, State};
	
	{error, Emsg} ->
	    {false, 
	     wrq:set_resp_body(to_binary(Emsg), ReqData),
	     State}
    end;

resource_exists(ReqData, State) ->
    {true, ReqData, State}.

%%
delete_resource(ReqData, #ctx{ano = Ano, bno = Bno,
			      switch = SwitchName} = State) ->
    case group_switch:disconnect(SwitchName, Ano, Bno) of
	ok ->
	    {true, 
	     wrq:set_resp_body(<<"ok">>, ReqData),
	     State#ctx{ano    = Ano,
		       switch = SwitchName}};
	
	{error, Emsg} ->
	    {false, 
	     wrq:set_resp_body(to_binary(Emsg), ReqData),
	     State}
    end.

%%
malformed_request(ReqData, State) ->
    SwitchName = wrq:path_info(switch_name, ReqData),
    Ano        = wrq:path_info(ano, ReqData),
    Bno        = wrq:path_info(bno, ReqData),

    case whereis(list_to_atom(SwitchName)) of
        Pid when is_pid(Pid) ->
	    {false, 
	     ReqData, 
	     State#ctx{switch = SwitchName,
		       ano    = Ano,
		       bno    = Bno
		      }};
	_ ->
            {true, ReqData, State#ctx{switch = SwitchName}}
    end.





