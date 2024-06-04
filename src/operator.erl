%%%-------------------------------------------------------------------
-module(operator).

%% API
-export([map/1,
         take/1,
         filter/1]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type t(A, ErrorInfo, B) :: fun((observable:item_producer(A, ErrorInfo)) -> observable:t(B, ErrorInfo)).

-define(operator(ItemProducer, State, OpDef),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    OpDef
                end
            )
        end
).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec map(MapFun :: fun((A) -> B)) -> t(A, ErrorInfo :: any(), B) when
    A :: any(),
    B :: any().
%%--------------------------------------------------------------------
map(MapFun) ->
    fun(ItemProducer) ->
        observable:create(
            fun(State) -> 
                {Item, NewState} = apply(ItemProducer, [State]),
                {observable_item:liftM(MapFun, Item), NewState}
            end
        )
    end.

%%--------------------------------------------------------------------
-spec filter(Pred) -> operator:t(A, ErrorInfo, A)
    when Pred :: fun((A) -> boolean()),
         A    :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
filter(Pred) ->
    fun(ItemProducer) ->
        observable:create(
            fun(State) ->
                {Item, NewState} = apply(ItemProducer, [State]),
                case observable_item:is_a_next_item(Item) andalso 
                       apply(Pred, [observable_item:get_value_from_next_item(Item)]) of
                        true ->
                            {observable_item:ignore(), NewState};
                        false ->
                            {Item, NewState}
                end
            end
        )
    end.


%%--------------------------------------------------------------------
-spec take(N :: integer()) -> operator:t(A, ErrorInfo, A)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
take(N) when N > 0 ->
    Ref = erlang:unique_integer(),
    fun(ItemProducer) ->
        observable:create(
            fun(State) ->
                case maps:get(Ref, State) of
                    0 -> 
                        {complete, State};
                    undefined -> 
                        {Item, NewState} = apply(ItemProducer, [State]),
                        {Item, maps:put(Ref, N - 1, NewState)};
                    NItem -> % TDOO add condition N is bigger or equal to zero
                        {Value, NewState} = apply(ItemProducer, [State]),
                        {Value, maps:put(NewState, Ref, NItem - 1)}
                end
            end
        )
    end.

-spec take_while(Pred) -> operator:t(A, ErrorInfo, A) when
    Pred :: fun((A) -> boolean()),
    A :: any(),
    ErrorInfo :: any().

take_while(Pred) ->
    %% double check Haskell's take_while
    fun(ItemProducer) ->
        observable:create(
            fun(State) ->
                {Item, NewState} = apply(ItemProducer, [State]),
                case observable_item:is_a_next_item(Item) of
                    false ->
                        {Item, NewState};
                    true ->


        )

%%%===================================================================
%%% Internal functions
%%%===================================================================
