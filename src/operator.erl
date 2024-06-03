%%%-------------------------------------------------------------------
-module(operator).

%% API
-export([map/1]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type t(A, ErrorInfo, B) :: fun((observable:item_producer(A, ErrorInfo)) -> observable:t(B, ErrorInfo)).


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
                {Value, NewState} = apply(ItemProducer, [State]),
                {observable_item:liftM(MapFun, Value), NewState}
            end
        )
    end.

% take(N) when > 0 ->
%     fun(ItemProducer) ->
%         observable:create(
%             fun(State) ->
%                 case maps:get(State, take_n) of
%                     0 - > 
%                         {complete, State};
%                     undefined -> 
%                         {Value, NewState} = apply(ItemProducer, [State]),
%                         {Value, maps:put(NewState, take_n, N - 1)};
%                     NItem ->
%                         {Value, NewState} = apply(ItemProducer, [State]),
%                         {Value, maps:put(NewState, take_n, NItem - 1)}
%                 end
%             end
%         )
%     end.
                

%%%===================================================================
%%% Internal functions
%%%===================================================================
