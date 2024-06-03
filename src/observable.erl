%%%-------------------------------------------------------------------
-module(observable).

%% API
-export([create/1,
         from_list/1,
         from_value/1,
         bind/2,
         subscribe/2]).

-export_type([t/2,
              item_producer/2]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type state() :: map().
-type item_producer(A, E) :: fun((state()) -> {observable_item:t(A, E), state()}).

-record(observable, {
    state            :: undefined | state(),
    item_producer    :: item_producer(any(), any()),
    subscribers = [] :: list(subscriber:t(any(), any()))
}).

-type t(A, ErrorInfo) :: #observable{
    state          :: any() | undefined,
    item_producer :: item_producer(A, ErrorInfo),
    subscribers    :: list(subscriber:t(A, ErrorInfo))
}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec create(ItemProducer) -> t(A, ErrorInfo) when
    ItemProducer :: item_producer(A, ErrorInfo),
    ErrorInfo     :: any(),
    A             :: any().
create(ItemProducer) ->
    #observable{item_producer = ItemProducer}.

%%--------------------------------------------------------------------
-spec bind(observable:t(A, ErrorInfo), operator:t(A, ErrorInfo, B)) 
         -> observable:t(B, ErrorInfo) 
            when A :: any(),
                 B :: any(),
                 ErrorInfo :: any().
%%--------------------------------------------------------------------
bind(ObservableA, Operator) ->
    apply(Operator, [ObservableA#observable.item_producer]).

%%--------------------------------------------------------------------
-spec subscribe(ObservableA, Subscribers) -> ok 
    when ObservableA :: observable:t(A, ErrorInfo),
         Subscribers  :: subscriber:t(A, ErrorInfo),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
subscribe(ObservableA, Subscribers) ->
    ObservableWithSubs = ObservableA#observable{subscribers = Subscribers},
    run(ObservableWithSubs).

%%--------------------------------------------------------------------
-spec from_list(List :: list(A)) -> observable:t(A, ErrorInfo)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
from_list([Head|Tail]) ->
    Ref = erlang:unique_integer(),
    ItemProducer =
     fun(State) ->
             case maps:get(Ref, State, undefined) of
                undefined ->
                    {observable_item:create(Head), _State = maps:put(Ref, Tail, State)};
                [] -> 
                    {observable_item:complete(), State};
                [Value|List] ->
                    {observable_item:create(Value), _State = maps:put(Ref, List, State)}
             end
     end,
    create(ItemProducer).

%%--------------------------------------------------------------------
-spec from_value(Value :: A) -> observable:t(A, ErrorInfo)
     when A :: any(),
          ErrorInfo :: any().
%%--------------------------------------------------------------------
from_value(Value) ->
    ItemProducer = fun(State) -> {observable_item:create(Value), State} end,
    create(ItemProducer).
    
      

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
-spec broadcast_item(CallbackFunName, Args, Subscribers) -> ok when
    CallbackFunName :: on_next | on_complete | on_error,
    Args :: list(A),
    Subscribers :: subscriber:t(A, ErrorInfo),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
broadcast_item(CallbackFunName, Args, Subscribers) ->
    [
        apply(CallbackFun, Args) 
        || Subscriber <- Subscribers,
           CallbackFun <- maps:get(CallbackFunName, Subscriber)
    ],
    ok.

%%--------------------------------------------------------------------
-spec run(ObservableA) -> ok
    when ObservableA :: observable:t(A, ErrorInfo),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(ObservableA) ->
    run(ObservableA, _State = maps:new()).

%%--------------------------------------------------------------------
-spec run(ObservableA, State) -> ok
    when ObservableA :: observable:t(A, ErrorInfo),
         State :: map(),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(#observable{item_producer = ItemProducer, subscribers = Subscribers} = ObservableA, State) ->
    {Item, NewState} = apply(ItemProducer, [State]),
    case Item of 
        {next, Value}      ->
            broadcast_item(on_next, [Value], Subscribers),
            run(ObservableA, NewState);
        {error, ErrorInfo} ->
            broadcast_item(on_error, [ErrorInfo], Subscribers);
        complete           -> 
            broadcast_item(on_complete, [], Subscribers);
        ignore             ->
            run(ObservableA, NewState)
    end,
    ok.