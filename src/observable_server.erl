-module(observable_server).
-behaviour(gen_server).

-export([start_link/1, start_link/2, subscribe/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("observable_server.hrl").
-include("observable_item.hrl").
-include("subscriber.hrl").

%%====================================================================
%% API functions
%%====================================================================

start_link(ItemProducer) ->
    gen_server:start_link(?MODULE, {ItemProducer, undefined}, []).

start_link(ItemProducer, Interval) when is_integer(Interval), Interval > 0 ->
    gen_server:start_link(?MODULE, {ItemProducer, Interval}, []).

subscribe(ServerPid, Subscriber) ->
    gen_server:cast(ServerPid, {subscribe, Subscriber}).

stop(ServerPid) ->
    gen_server:cast(ServerPid, stop).

%%====================================================================
%% Gen Server Callbacks
%%====================================================================

init({ItemProducer, Interval}) ->
    State = #state{
        item_producer = ItemProducer,
        interval = Interval
    },
    {ok, schedule_next(State)}.

handle_call(emit, _From, State = #state{queue = []}) ->
    {reply, ignore, State};
handle_call(emit, _From, State = #state{queue = [Value|Rest]}) ->
    {reply, Value, State#state{queue = Rest}};

handle_call(emit, _From, State = #state{item_producer = ItemProducer, inner_state = InnerState}) ->
    {Item, NewInnerState} = apply(ItemProducer, [InnerState]),
    NewState = State#state{inner_state = NewInnerState},
    case Item of
        ?NEXT(Value) ->
            {reply, Value, NewState};
        ?IGNORE ->
            {reply, ?IGNORE, NewState};
        ?LAST(Value) ->
            {stop, last, Value, NewState};
        ?ERROR(Error) ->
            {stop, error, Error, NewState};
        ?COMPLETE->
            {stop, ?COMPLETE, NewState}
    end;
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({subscribe, Subscriber}, State = #state{subscribers = Subs}) ->
    {noreply, State#state{subscribers = [Subscriber|Subs]}};

handle_cast(stop, State) ->
    {stop, normal, State}.

% handle_info(emit, State = #state{item_producer = Producer, inner_state = InnerState, subscribers = Subs}) ->
%     case apply(Producer, [InnerState]) of
%         {?NEXT(Value), NewInnerState} ->
%             broadcast_to_subscribers(?ON_NEXT, [Value], Subs),
%             {noreply, schedule_next(State#state{inner_state = NewInnerState})};
%         {?LAST(Value), NewInnerState} ->
%             broadcast_to_subscribers(?ON_NEXT, [Value], Subs),
%             broadcast_to_subscribers(?ON_COMPLETE, [], Subs),
%             {stop, normal, State#state{inner_state = NewInnerState}};
%         {?ERROR(Error), NewInnerState} ->
%             broadcast_to_subscribers(?ON_ERROR, [Error], Subs),
%             {stop, normal, State#state{inner_state = NewInnerState}};
%         {?COMPLETE, NewInnerState} ->
%             broadcast_to_subscribers(?ON_COMPLETE, [], Subs),
%             {stop, normal, State#state{inner_state = NewInnerState}};
%         {?IGNORE, NewInnerState} ->
%             {noreply, schedule_next(State#state{inner_state = NewInnerState})}
%     end;

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

schedule_next(State = #state{interval = undefined}) ->
    self() ! emit,
    State;
schedule_next(State = #state{interval = Interval, timer_ref = OldTimer}) ->
    cancel_timer(OldTimer),
    TimerRef = erlang:send_after(Interval, self(), emit),
    State#state{timer_ref = TimerRef}.

cancel_timer(undefined) -> ok;
cancel_timer(TimerRef) -> erlang:cancel_timer(TimerRef).

broadcast_to_subscribers(CallbackType, Args, Subscribers) ->
    lists:foreach(fun(Sub) ->
        case subscriber:get_callback_function(CallbackType, Sub) of
            undefined -> ok;
            Callback -> apply(Callback, Args)
        end
    end, Subscribers).
