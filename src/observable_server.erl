-module(observable_server).
-behaviour(gen_server).

-export([start_link/1, subscribe/2, unsubscribe/2, stop/1, process_item/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("observable_server.hrl").
-include("observable_item.hrl").

%%====================================================================
%% API functions
%%====================================================================

start_link(InitFun) ->
    gen_server:start_link(?MODULE, InitFun, []).

subscribe(ServerPid, Subscriber) ->
    gen_server:cast(ServerPid, {subscribe, Subscriber}).

%%--------------------------------------------------------------------
%% @doc Removes a subscriber from the observable
%% @param ServerPid The pid of the observable server
%% @param Subscriber The subscriber to remove
%% @end
%%--------------------------------------------------------------------
unsubscribe(ServerPid, Subscriber) ->
    gen_server:cast(ServerPid, {unsubscribe, Subscriber}).

stop(ServerPid) ->
    gen_server:cast(ServerPid, stop).

%%--------------------------------------------------------------------
%% @doc Processes an item through the server
%% @param ServerPid The server process PID
%% @param Item The item to process
%% @return The processed result
%% @end  
%%--------------------------------------------------------------------
-spec process_item(pid()) -> ?NEXT(Value) | ?IGNORE | ?COMPLETE | ?ERROR(ErrorInfo) when
    Value :: term(),
    ErrorInfo :: term().
process_item(ServerPid) ->
    gen_server:call(ServerPid, process_item).

%%====================================================================
%% Gen Server Callbacks
%%====================================================================

init(InitFun) ->
    State = apply(InitFun, []),
    {ok, State}.

handle_call(process_item, _From, State = #state{item_producer = ItemProducer, inner_state = InnerState}) ->
    {Item, NewInnerState} = apply(ItemProducer, [InnerState]),
    NewState = State#state{inner_state = NewInnerState},
    case Item of
        ?NEXT(Value) ->
            {reply, ?NEXT(Value), NewState};
        ?IGNORE ->
            {reply, ?IGNORE, NewState};
        ?HALT ->
            {reply, ?HALT, NewState};
        ?LAST(Value) ->
            {stop, normal, ?LAST(Value), NewState};
        ?ERROR(Error) ->
            {stop, error, ?ERROR(Error), NewState};
        ?COMPLETE->
            {stop, normal, ?COMPLETE, NewState}
    end.


handle_cast({subscribe, Subscriber}, State = #state{subscribers = Subs}) ->
    {noreply, State#state{subscribers = [Subscriber|Subs]}};

handle_cast({unsubscribe, Subscriber}, State = #state{subscribers = Subs}) ->
    % Remove the subscriber from the list
    NewSubs = lists:filter(fun(Sub) -> Sub =/= Subscriber end, Subs),
    {noreply, State#state{subscribers = NewSubs}};

handle_cast(stop, State) ->
    {stop, normal, State};

handle_cast(Requst, #state{cast_handler = CastHandler} = State) ->
    case apply(CastHandler, [Requst, State]) of
        {noreply, NewState} -> {noreply, NewState};
        {stop, Reason, NewState} -> {stop, Reason, NewState}
    end.


handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{timer_ref = TimerRef}) ->
    cancel_timer(TimerRef),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

cancel_timer(undefined) -> ok;
cancel_timer(TimerRef) -> erlang:cancel_timer(TimerRef).


