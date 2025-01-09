%%%-------------------------------------------------------------------
-module(operator).

%% API
-export([map/1,
         any/1,
         all/1,
         drop/1,
         drop_while/1,
         take/1,
         take_while/1,
         filter/1]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type t(A, ErrorInfo, B) :: fun((observable:item_producer(A, ErrorInfo)) -> observable:t(B, ErrorInfo)).

-define(operator(ItemProducer, State, OpDef),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    OpDef
                end
            )
        end
).

-define(stateful_operator(ItemProducer, Ref, State, DefaultState, StateHandling1, StateHandling2),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    case maps:get(Ref, State, DefaultState) of
                      StateHandling1;
                      StateHandling2
                    end
                end
            )
        end
).

-define(state_handling(State, StateHandling), State -> StateHandling).

-define(default_operator(Handler),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(BaseState) ->
                    {ProducedItem, ProducedState} = apply(ItemProducer, [BaseState]),
                    Handler(ProducedItem, BaseState, ProducedState, Ref)
                end
            )
        end
).

-define(stateless_operator(Handler),
        fun(ItemProducer) ->
            observable:create(
                fun(BaseState) ->
                    {ProducedItem, ProducedState} = apply(ItemProducer, [BaseState]),
                    {Handler(ProducedItem), ProducedState}
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
    ?stateless_operator(
        fun(Item) ->
            observable_item:liftM(MapFun, Item)
        end
    ).

%%--------------------------------------------------------------------
-spec filter(Pred) -> operator:t(A, ErrorInfo, A)
    when Pred :: fun((A) -> boolean()),
         A    :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
filter(Pred) ->
    ?stateless_operator(
        fun({next, Value}) ->
              case Pred(Value) of
                true -> observable_item:create(Value);
                false -> observable_item:ignore()
              end;
           (Item) -> Item   
        end
    ).

%%--------------------------------------------------------------------
-spec take(N :: integer()) -> operator:t(A, ErrorInfo, A)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
% take(N) when N >= 0 ->
%     Ref = erlang:unique_integer(),
%     ?operator(ItemProducer, St,
%         begin
%             State = add_new_state_field(Ref, N, St),
%             case maps:get(Ref, State, undefined) of
%                 0 -> 
%                     {complete, State};
%                 NItem -> % TDOO add condition N is bigger or equal to zero
%                     {Item, NewState} = apply(ItemProducer, [State]),
%                     case observable_item:is_a_next_item(Item) of
%                         true ->
%                             {Item, maps:put(Ref, NItem - 1, NewState)};
%                         false ->
%                             {Item, NewState}
%                     end
%             end
%         end).
take(N) when N >= 0 ->
    % Ref = erlang:unique_integer(),
    ?operator(ItemProducer, St,
        begin
            State = add_new_state_field(Ref, N, St),
            case maps:get(Ref, State, undefined) of
                0 -> 
                    {complete, State};
                NItem -> % TDOO add condition N is bigger or equal to zero
                    {Item, NewState} = apply(ItemProducer, [State]),
                    case observable_item:is_a_next_item(Item) of
                        true ->
                            {Item, maps:put(Ref, NItem - 1, NewState)};
                        false ->
                            {Item, NewState}
                    end
            end
        end).

%%--------------------------------------------------------------------
-spec take_while(Pred) -> operator:t(A, ErrorInfo, A) when
    Pred :: fun((A) -> boolean()),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
take_while(Pred) ->
    %% double check Haskell's take_while
    ?operator(ItemProducer, State,
        begin
            {Item, NewState} = apply(ItemProducer, [State]),
            {
                observable_item:bind(Item, fun(Value) ->
                                             case Pred(Value) of
                                                true  -> observable_item:create(Value);
                                                false -> observable_item:complete()
                                             end
                                           end),
                NewState
            }
        end).

% %%--------------------------------------------------------------------
% -spec any(Pred) -> observable_item:t(A, ErrorInfo)
%     when
%         Pred :: fun((A) -> boolean()),
%         A    :: any(),
%         ErrorInfo :: any().
% %%--------------------------------------------------------------------
% any(Pred) ->
%     Ref = erlang:unique_integer(),
%     ?operator(ItemProducer, State,
%         begin
%             case maps:get(Ref, State, uncompleted) of
%                 completed ->
%                     {observable_item:complete(), State};
%                 uncompleted ->
%                     {Item, NewState} = apply(ItemProducer, [State]),
%                     case Item of
%                         complete ->
%                             {observable_item:create(false), maps:put(Ref, completed, NewState)};
%                         {next, Value} ->
%                             case Pred(Value) of
%                                 true  -> {observable_item:create(true), maps:put(Ref, completed, NewState)};
%                                 false -> {observable_item:ignore(), maps:put(Ref, uncompleted, NewState)}
%                             end;
%                         Item ->
%                             {Item, NewState}
%                     end
%             end
%         end
%     ).
any(Pred) ->
    ?default_operator(
        fun({next, Value}, _State, NewState, _StRef) ->
             case Pred(Value) of
                true  -> {observable_item:create(true), mark_observable_as_completed(NewState)};
                false -> {observable_item:ignore(), NewState}
             end;
           (complete, _State, NewState, _StRef) ->
                {observable_item:create(false), mark_observable_as_completed(NewState)};
           (Item, _State, NewState, _StRef) ->
                {Item, NewState}
       end
    ).
    % ?stateful_operator(ItemProducer, Ref, State, _DefaultState = uncompleted,
    %     ?state_handling(
    %         _State = completed,
    %         {observable_item:complete(), State}
    %     ),
    %     ?state_handling(
    %         _State = uncompleted,
    %         begin
    %             {Item, NewState} = apply(ItemProducer, [State]),
    %             case Item of
    %                 complete ->
    %                     {observable_item:create(false), maps:put(Ref, completed, NewState)};
    %                 {next, Value} ->
    %                     case Pred(Value) of
    %                         true  -> {observable_item:create(true), maps:put(Ref, completed, NewState)};
    %                         false -> {observable_item:ignore(), maps:put(Ref, uncompleted, NewState)}
    %                     end;
    %                 Item ->
    %                     {Item, NewState}
    %             end
    %         end
    %     )
    % ).

%%--------------------------------------------------------------------
-spec all(Pred) -> observable_item:t(A, ErrorInfo)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
all(Pred) ->
    ?default_operator(
        fun({next, Value}, _State, NewState, _StRef) ->
              case Pred(Value) of
                true  -> {observable_item:ignore(), NewState};
                false -> {observable_item:create(false), mark_observable_as_completed(NewState)}
              end;
           (complete, _State, NewState, _StRef) ->
                {observable_item:create(true), mark_observable_as_completed(NewState)};
           (Item, _State, NewState, _StRef) ->
                {Item, NewState}
        end
    ).

% drop(N) ->
%     Ref = erlang:unique_integer(),
%     ?operator(ItemProducer, State, 
%         begin
%             NItemLeftToDrop = maps:get(Ref, State, N),
%             ?default_operator_behavior(ItemProducer, Item, State, NewState,
%                 case NItemLeftToDrop > 0 of
%                     true ->
%                         observable_item:ignore();
%                     false ->
%                         Item
%                 end,
%                 case observable_item:is_a_next_item(Item) of
%                     true ->
%                         maps:put(Ref, NItemLeftToDrop - 1, NewState);
%                     false ->
%                         maps:put(Ref, NItemLeftToDrop, NewState)
%                 end
%             )
%         end).

%%--------------------------------------------------------------------
-spec drop(N :: non_neg_integer()) -> operator:t(any(), any(), any()).
%%--------------------------------------------------------------------
drop(N) ->
    ?default_operator(
        fun(Item, State, NewState, StRef) ->
            NItemLeftToDrop = maps:get(StRef, State, N),
            case Item of
                {next, _Value} when NItemLeftToDrop > 0 ->
                    {observable_item:ignore(), maps:put(StRef, NItemLeftToDrop - 1, NewState)};
                Item ->
                    {Item, maps:put(StRef, NItemLeftToDrop, NewState)}
            end
        end
    ).

%%--------------------------------------------------------------------
-spec drop_while(Pred) -> operator:t(A, ErrorInfo, A)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
drop_while(Pred) ->
    %% double check Haskell's take_while
    % Ref = erlang:unique_integer(),
    ?operator(ItemProducer, State,
        begin
            MustDrop = maps:get(Ref, State, true),
            {Item, NewState} = apply(ItemProducer, [State]),
            case MustDrop of
                false ->
                    {Item, NewState};
                true ->
                    drop_item(Item, Pred, NewState, Ref)
            end
        end).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
-spec add_new_state_field(Key, Value, State) -> map() when
    Key :: any(),
    Value :: any(),
    State :: map().
%%--------------------------------------------------------------------
add_new_state_field(Key, Value, State) ->
    case maps:get(Key, State, undefined) of
        undefined ->
            maps:put(Key, Value, State);
        _ ->
            State
    end.

%%--------------------------------------------------------------------
-spec mark_observable_as_completed(State :: observable:state()) -> map().
%%--------------------------------------------------------------------
mark_observable_as_completed(State) ->
    maps:put(is_completed, true, State).

%%--------------------------------------------------------------------
-spec drop_item(Item, MustDropPred, State, MustDropRef) -> {observable_item:t(A, ErrorInfo), map()} when
    Item :: observable_item:t(A, ErrorInfo),
    A :: any(),
    ErrorInfo :: any(),
    MustDropPred :: fun((A) -> boolean()),
    State :: map(),
    MustDropRef :: any().
%%--------------------------------------------------------------------
drop_item({next, Value} = Item, MustDropPred, State, MustDropRef) ->
    case MustDropPred(Value) of
        true ->
            {observable_item:ignore(), maps:put(MustDropRef,  true, State)};
        false ->
            {Item, maps:put(MustDropRef, false, State)}
    end;
drop_item(Item, _MustDropPred, State, MustDropRef) ->
    {Item, maps:put(MustDropRef, true, State)}.

