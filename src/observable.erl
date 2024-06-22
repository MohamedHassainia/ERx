%%%-------------------------------------------------------------------
-module(observable).

%% API
-export([create/1,
         from_list/1,
         from_value/1,
         zip2/2,
         zip/1,
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
    state          :: state() | undefined,
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
-spec subscribe(ObservableA, Subscribers) -> any() 
    when ObservableA :: observable:t(A, ErrorInfo),
         Subscribers  :: list(subscriber:t(A, ErrorInfo)),
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
    
-spec zip2(ObservableA, ObservableB) -> ObservableC
    when ObservableA :: observable:t(A, ErrorInfo),
         ObservableB :: observable:t(B, ErrorInfo),
         ObservableC :: observable:t({A, B}, ErrorInfo),
         A :: any(),
         B :: any(),
         ErrorInfo :: any().

%% TODO fix this observable
zip2(#observable{item_producer = ItemProducerA} = _ObservableA,
     #observable{item_producer = ItemProducerB} = _ObservableB) ->
    create(
        fun(State) ->
            {ItemA, NewStateA} = apply(ItemProducerA, [State]),
            {ItemB, NewStateB} = apply(ItemProducerB, [State]),
            NewState = maps:merge(NewStateA, NewStateB),
            {{ItemA, ItemB}, NewState}
        end      
    ).

-spec zip(Observables) -> Observable
    when Observable :: observable:t(list(), ErrorInfo),
         Observables :: list(observable:t(A, ErrorInfo)),
         A :: any(),
         ErrorInfo :: any().

zip(Observables) ->
    create(
        fun(State) ->
            apply_zipped_observables(Observables, [], State)
        end
    ).

%%--------------------------------------------------------------------    
-spec apply_zipped_observables(Observables, Result, State) -> {observable_item:t(list(), ErrorInfo), state()} when
    Observables :: [observable:t(A, ErrorInfo)],
    Result      :: list(),
    State       :: state(),
    A           :: any(),
    ErrorInfo   :: any().
%%--------------------------------------------------------------------
apply_zipped_observables([], Result, State) ->
    {{next, Result}, State};
apply_zipped_observables([Observable | Observables], Result, State) ->
    #observable{item_producer = ItemProducer} = Observable,
    
     case apply(ItemProducer, [State]) of
        {ignore, NewState} -> 
            MergedNewState = maps:merge(State, NewState),
            apply_zipped_observables(Observables, Result, MergedNewState);
        {{next, Item}, NewState} ->
            MergedNewState = maps:merge(State, NewState),
            apply_zipped_observables(Observables, [Item|Result], MergedNewState);
        {{error, ErrorInfo}, NewState} ->
            {{error, ErrorInfo}, maps:merge(State, NewState)};
        {complete, NewState} ->
            {complete, maps:merge(State, NewState)}
    end.
            



%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
-spec broadcast_item(CallbackFunName, Args, Subscribers) -> list() when
    CallbackFunName :: on_next | on_complete | on_error,
    Args :: list(),
    Subscribers :: list(subscriber:t(A, ErrorInfo)),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
broadcast_item(CallbackFunName, Args, Subscribers) ->
    SubsCallbackFuns = 
        [subscriber:get_callback_function(CallbackFunName, Subscriber) || Subscriber <- Subscribers],

    [apply(CallbackFun, Args) ||  CallbackFun <- SubsCallbackFuns, CallbackFun /= undefined].

%%--------------------------------------------------------------------
-spec run(ObservableA) -> any()
    when ObservableA :: observable:t(A, ErrorInfo),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(ObservableA) ->
    run(ObservableA, _State = maps:new()).

%%--------------------------------------------------------------------
-spec run(ObservableA, State) -> any()
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
    end.