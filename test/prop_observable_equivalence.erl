-module(prop_observable_equivalence).
-include_lib("proper/include/proper.hrl").
-include("observable_item.hrl").

-export([
    prop_map_equivalence/0,
    prop_filter_equivalence/0, 
    prop_take_equivalence/0,
    prop_reduce_equivalence/0,
    prop_random_pipe_equivalence/0,
    prop_random_async_pipe_equivalence/0
]).

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%

%% Tests that observable map produces the same results as lists:map
prop_map_equivalence() ->
    ?FORALL({List, {MappingF, MappingDesc}}, {list(integer()), mapping_fun()},
        begin
            % Create an observable with map operation
            Observable = observable:bind(observable:from_list(List), operator:map(MappingF)),
            
            % Get observable results
            ObsResult = collect_observable_values(Observable),
            
            % Get list results
            ListResult = lists:map(MappingF, List),
            
            % Log for debugging
            case ObsResult =:= ListResult of
                false ->
                    io:format("Map function: ~p~nInput list: ~p~nObservable result: ~p~nList result: ~p~n", 
                              [MappingDesc, List, ObsResult, ListResult]);
                true -> ok
            end,
            
            % Check equivalence
            ObsResult =:= ListResult
        end).

%% Tests that observable filter produces same results as lists:filter
prop_filter_equivalence() ->
    ?FORALL({List, {PredicateF, PredicateDesc}}, {list(integer()), predicate_fun()},
        begin
            Observable = observable:bind(observable:from_list(List), operator:filter(PredicateF)),
            ObsResult = collect_observable_values(Observable),
            ListResult = lists:filter(PredicateF, List),
            
            ObsResult =:= ListResult
        end).

%% Tests that observable take produces same results as lists:sublist
prop_take_equivalence() ->
    ?FORALL({List, N}, {list(integer()), non_neg_integer()},
        begin
            Observable = observable:bind(observable:from_list(List), operator:take(N)),
            ObsResult = collect_observable_values(Observable),
            ListResult = lists:sublist(List, N),
            
            ObsResult =:= ListResult
        end).

%% Tests that observable reduce produces same results as lists:foldl
prop_reduce_equivalence() ->
    ?FORALL({List, {ReduceF, ReduceDesc}, InitValue}, {non_empty(list(integer())), reduce_fun(), integer()},
        begin
            Observable = observable:bind(observable:from_list(List), operator:reduce(ReduceF, InitValue)),
            ObsResult = collect_last_value(Observable),
            ListResult = lists:foldl(ReduceF, InitValue, List),
            
            ObsResult =:= ListResult
        end).

%% Tests random combinations of operators against equivalent list operations
prop_random_pipe_equivalence() ->
    ?FORALL({List, Operations}, {list(integer()), list(operator_spec())},
        begin
            % Skip empty operation lists
            case Operations of
                [] -> true;
                _ ->
                    % Create observable pipeline
                    Operators = [operator_from_spec(Op) || Op <- Operations],
                    Observable = observable:pipe(observable:from_list(List), Operators),
                    
                    % Apply operations to list
                    ObsResult = collect_observable_values(Observable),
                    ListResult = apply_list_operations(List, Operations),
                    
                    % Debug output for failures
                    case ObsResult =:= ListResult of
                        false ->
                            io:format("Operations: ~p~nInput: ~p~nObservable: ~p~nList result: ~p~n", 
                                     [Operations, List, ObsResult, ListResult]);
                        true -> ok
                    end,
                    
                    % Check equivalence
                    ObsResult =:= ListResult
            end
        end).

%% Tests random combinations with async operators
prop_random_async_pipe_equivalence() ->
    ?FORALL({List, Operations}, {list(integer()), non_empty(list(operator_spec()))},
        begin
            % Add async operators at random positions
            AsyncOperations = inject_async_operators(Operations),
            
            % Create observable pipeline
            Operators = [operator_from_spec(Op) || Op <- AsyncOperations],
            Observable = observable:pipe(observable:from_list(List), Operators),
            
            % Get observable results with time for async operations
            ObsResult = collect_observable_values_with_delay(Observable, 100),
            
            % Apply non-async operations to list
            ListResult = apply_list_operations(List, Operations),
            
            % Check equivalence
            lists:sort(ObsResult) =:= lists:sort(ListResult)
        end).

%%%%%%%%%%%%%%%%%%
%%% Generators %%%
%%%%%%%%%%%%%%%%%%

% Generator for mapping functions with descriptive name
mapping_fun() ->
    oneof([
        {fun(X) -> X * 2 end, "double"},
        {fun(X) -> X + 10 end, "add_10"},
        {fun(X) -> X * X end, "square"},
        {fun(X) -> -X end, "negate"},
        {fun(X) -> X rem 10 end, "mod_10"}
    ]).

% Generator for predicate functions
predicate_fun() ->
    oneof([
        {fun(X) -> X > 0 end, "positive"},
        {fun(X) -> X rem 2 =:= 0 end, "even"},
        {fun(X) -> X rem 2 =:= 1 end, "odd"},
        {fun(X) -> X =< 10 end, "leq_10"},
        {fun(X) -> X rem 3 =:= 0 end, "div_by_3"}
    ]).

% Generator for reduce functions
reduce_fun() ->
    oneof([
        {fun(X, Acc) -> X + Acc end, "sum"},
        {fun(X, Acc) -> X * Acc end, "product"},
        {fun(X, Acc) -> max(X, Acc) end, "max"},
        {fun(X, Acc) -> min(X, Acc) end, "min"}
    ]).

% Generator for operator specifications
operator_spec() ->
    oneof([
        {map, elements([
            {fun(X) -> X * 2 end, "double"},
            {fun(X) -> X + 5 end, "add_5"},
            {fun(X) -> X * X end, "square"}
        ])},
        {filter, elements([
            {fun(X) -> X > 0 end, "positive"},
            {fun(X) -> X rem 2 =:= 0 end, "even"},
            {fun(X) -> X rem 3 =:= 0 end, "div_by_3"}
        ])},
        {take, choose(1, 10)},
        {take_while, elements([
            {fun(X) -> X < 20 end, "less_than_20"},
            {fun(X) -> X > -5 end, "greater_than_neg5"},
            {fun(X) -> X rem 5 =:= 0 end, "div_by_5"}
        ])},
        {drop, choose(0, 5)}
    ]).

% Add async operators at random positions
inject_async_operators(Operations) ->
    inject_async_randomly(Operations, rand:uniform(3)).  % Insert 1-3 async operators

inject_async_randomly(Operations, 0) ->
    Operations;
inject_async_randomly(Operations, N) when N > 0 ->
    case length(Operations) of
        0 -> Operations;
        Len ->
            Position = rand:uniform(Len),
            Before = lists:sublist(Operations, Position - 1),
            After = lists:nthtail(Position - 1, Operations),
            NewOps = Before ++ [{async, dummy}] ++ After,
            inject_async_randomly(NewOps, N - 1)
    end.

%%%%%%%%%%%%%%%%%%
%%% Helpers %%%
%%%%%%%%%%%%%%%%%%

% Convert operator specification to actual operator function
operator_from_spec({map, {Fun, _Desc}}) ->
    operator:map(Fun);
operator_from_spec({filter, {Fun, _Desc}}) ->
    operator:filter(Fun);
operator_from_spec({take, N}) ->
    operator:take(N);
operator_from_spec({take_while, {Fun, _Desc}}) ->
    operator:take_while(Fun);
operator_from_spec({drop, N}) ->
    operator:drop(N);
operator_from_spec({distinct, _}) ->
    operator:distinct();
operator_from_spec({async, _}) ->
    operator:async().

% Apply operations to a list - simulating what the observable would do
apply_list_operations(List, []) -> 
    List;
apply_list_operations(List, [{map, {Fun, _}} | Rest]) ->
    apply_list_operations(lists:map(Fun, List), Rest);
apply_list_operations(List, [{filter, {Pred, _}} | Rest]) ->
    apply_list_operations(lists:filter(Pred, List), Rest);
apply_list_operations(List, [{take, N} | Rest]) ->
    apply_list_operations(lists:sublist(List, N), Rest);
apply_list_operations(List, [{take_while, {Pred, _}} | Rest]) ->
    apply_list_operations(lists:takewhile(Pred, List), Rest);
apply_list_operations(List, [{drop, N} | Rest]) ->
    apply_list_operations(lists:nthtail(min(N, length(List)), List), Rest);

apply_list_operations(List, [{async, _} | Rest]) ->
    % Async doesn't change values, just the execution model
    apply_list_operations(List, Rest).

% Collect values from observable
collect_observable_values(Observable) ->
    Table = ets:new(values_table, [duplicate_bag]),
    Subscriber = subscriber:create(
        fun(Value) -> ets:insert(Table, {value, Value}) end
    ),
    
    observable:subscribe(Observable, Subscriber),
    
    Values = [V || {_, V} <- ets:lookup(Table, value)],
    ets:delete(Table),
    Values.

% Collect values with a delay for async operations
collect_observable_values_with_delay(Observable, Delay) ->
    Table = ets:new(values_table, [duplicate_bag]),
    CompletionRef = make_ref(),
    
    Subscriber = subscriber:create(
        fun(Value) -> ets:insert(Table, {value, Value}) end,
        fun(_) -> ok end,
        fun() -> ets:insert(Table, {completion, CompletionRef}) end
    ),
    
    observable:subscribe(Observable, Subscriber),
    
    % Wait for completion or timeout
    timer:sleep(Delay),
    
    Values = [V || {_, V} <- ets:lookup(Table, value)],
    ets:delete(Table),
    Values.

% Collect the last value from an observable (for reduce tests)
collect_last_value(Observable) ->
    Table = ets:new(value_table, [duplicate_bag]),
    
    Subscriber = subscriber:create(
        fun(Value) -> 
            % Overwrite any previous value to keep only the last one
            ets:delete_all_objects(Table),
            ets:insert(Table, {last_value, Value})
        end
    ),
    
    observable:subscribe(Observable, Subscriber),
    
    case ets:lookup(Table, last_value) of
        [{_, Value}] -> Value;
        [] -> undefined
    end.
