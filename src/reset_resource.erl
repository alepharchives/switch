%% @author Torbjorn Tornkvist <tobbe@tornkvist.org>
%% @copyright 2011 Torbjorn Tornkvist
%% @doc A simple phone switch simulator.

-module(reset_resource).
-export([init/1
         , allowed_methods/2
         , content_types_accepted/2
         , content_types_provided/2
         , malformed_request/2
         , resource_exists/2
         , to_text/2
        ]).

-import(switch, [to_binary/1]).

-include_lib("webmachine/include/webmachine.hrl").

-record(ctx, {
	  ano,
          method,
          switch
         }).
          

init([]) ->
    {ok, #ctx{}}.
%%    {{trace, "/tmp"}, #ctx{}}. % when debugging!

%%
allowed_methods(ReqData, State) ->
    {['PUT'], ReqData, State#ctx{method = wrq:method(ReqData)}}.

%%
content_types_accepted(ReqData, State) ->
      {[{"text/plain", to_text}], ReqData, State}.

%%
content_types_provided(ReqData, State) ->
      {[{"text/plain", to_text}], ReqData, State}.

%%
to_text(ReqData, State) ->
    {<<"">>, ReqData, State}.

%%
resource_exists(ReqData, #ctx{method = 'PUT'} = State) ->
    SwitchName = wrq:path_info(switch_name, ReqData),
    Ano        = wrq:path_info(ano, ReqData),

    case group_switch:reset(SwitchName, Ano) of
	ok ->
	    {true, ReqData, State#ctx{ano    = Ano,
				      switch = SwitchName}};
	
	{error, Emsg} ->
	    {false, 
	     wrq:set_resp_body(to_binary(Emsg), ReqData),
	     State}
    end;

resource_exists(ReqData, State) ->
    {true, ReqData, State}.

%%
malformed_request(ReqData, State) ->
    SwitchName = wrq:path_info(switch_name, ReqData),
    case whereis(list_to_atom(SwitchName)) of
        Pid when is_pid(Pid) ->
            {false, ReqData, State#ctx{switch = SwitchName}};
        _  ->
            {true, ReqData, State#ctx{switch = SwitchName}}
    end.





