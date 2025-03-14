-module(prop_process_cleanup).
-include_lib("proper/include/proper.hrl").
-include("observable_item.hrl").

-export([prop_async_cleanup/0, prop_combined_operators_cleanup/0, prop_nested_async_cleanup/0]).

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%

%% Tests that processes created by async observables are properly terminated
prop_async_cleanup() ->
    ?FORALL(List, non_empty(list(integer())),
        begin
            % Check initial process count
            InitialProcessCount = count_processes(),
            
            % Create a simple async observable
            AsyncObs = observable:bind(
                observable:from_list(List),
                operator:async()
            ),
            
            % Subscribe with a dummy subscriber to force execution
            Subscriber = subscriber:create(fun(_) -> ok end),
            observable:subscribe(AsyncObs, Subscriber),
            
            % Allow some time for async execution and cleanup
            timer:sleep(50),
            
            % Check final process count - should be the same as initial
            FinalProcessCount = count_processes(),
            InitialProcessCount =:= FinalProcessCount
        end).

%% Tests combinations of different operators with async
prop_combined_operators_cleanup() ->
    ?FORALL({List, TakeCount}, {non_empty(list(integer())), pos_integer()},
        begin
            InitialProcessCount = count_processes(),
            
            % Create a complex observable with multiple operators and async
            ComplexObs = observable:pipe(
                observable:from_list(List),
                [
                    % First transform synchronously
                    operator:filter(fun(X) -> X rem 2 =:= 0 end),
                    operator:map(fun(X) -> X * 2 end),
                    
                    % Then make it async
                    operator:async(),
                    
                    % Then apply more operators
                    operator:take(min(TakeCount, 10)), % Limit to avoid excessive computation
                    operator:map(fun(X) -> X + 1 end)
                ]
            ),
            
            % Subscribe and wait for completion
            Table = ets:new(result_table, [duplicate_bag]),
            Subscriber = subscriber:create(
                fun(Val) -> ets:insert(Table, {val, Val}) end,
                fun(_) -> ets:insert(Table, {error, true}) end,
                fun() -> ets:insert(Table, {complete, true}) end
            ),
            
            observable:subscribe(ComplexObs, Subscriber),
            
            % Allow time for completion
            timer:sleep(100),
            
            % Verify all values were received
            Results = [V || {val, V} <- ets:lookup(Table, val)],
            IsCompleted = ets:member(Table, complete),
            ets:delete(Table),
            
            % Calculate expected results
            ExpectedVals = lists:sublist(
                [X * 2 + 1 || X <- List, X rem 2 =:= 0],
                min(TakeCount, 10)
            ),
            
            % Verify process count returned to initial and results are correct
            FinalProcessCount = count_processes(),
            (InitialProcessCount =:= FinalProcessCount) andalso
            (lists:sort(Results) =:= lists:sort(ExpectedVals)) andalso
            IsCompleted
        end).

%% Tests nested async operators to ensure all processes are cleaned up
prop_nested_async_cleanup() ->
    ?FORALL(Lists, non_empty(list(non_empty(list(integer())))),
        begin
            InitialProcessCount = count_processes(),
            
            % Create a list of async observables
            AsyncObservables = [
                observable:bind(observable:from_list(List), operator:async())
                || List <- Lists
            ],
            
            % Merge them, which creates an observable of the merged results
            MergedObs = observable:merge(AsyncObservables),
            
            % Apply another async operator on top
            DoublyAsyncObs = observable:bind(MergedObs, operator:async()),
            
            % Final transform
            FinalObs = observable:bind(
                DoublyAsyncObs, 
                operator:map(fun(X) -> X * 10 end)
            ),
            
            % Subscribe and collect results
            Results = ets:new(nested_results, [duplicate_bag]),
            Subscriber = subscriber:create(
                fun(Val) -> ets:insert(Results, {val, Val}) end,
                fun(_) -> ok end,
                fun() -> ets:insert(Results, {complete, true}) end
            ),
            
            observable:subscribe(FinalObs, Subscriber),
            
            % Allow more time for nested async operations
            timer:sleep(200),
            
            % Get results and check completeness
            CollectedValues = [V || {val, V} <- ets:lookup(Results, val)],
            IsCompleted = ets:member(Results, complete),
            ets:delete(Results),
            
            % Calculate expected 
            ExpectedValues = [X * 10 || X <- lists:append(Lists)],
            
            % Verify process cleanup and correct results
            FinalProcessCount = count_processes(),
            (InitialProcessCount =:= FinalProcessCount) andalso
            (lists:sort(CollectedValues) =:= lists:sort(ExpectedValues)) andalso
            IsCompleted
        end).

%%--------------------------------------------------------------------
%% Helper function to count currently running processes
%%--------------------------------------------------------------------
count_processes() ->
    length(processes()).


