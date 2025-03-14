-module(prop_async_observable).
-include_lib("proper/include/proper.hrl").
-include("observable_item.hrl").

-export([prop_merge_sync_async/0, prop_zip_random_async/0]).

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%

% Test merging sync and async observables

prop_merge_sync_async() ->
    ?FORALL({List1, List2}, {list(integer()), list(integer())},
        begin
            % Create a sync observable and an async observable
            SyncObs = observable:from_list(List1),
            AsyncObs = observable:bind(observable:from_list(List2), operator:async()),
            
            % Merge them
            MergedObs = observable:merge([SyncObs, AsyncObs]),
            
            % Track results
            Table = ets:new(items_table, [duplicate_bag]),
            Subscriber = create_collecting_subscriber(Table),
            
            % Subscribe and wait for completion
            observable:subscribe(MergedObs, Subscriber),
            timer:sleep(100), % Give async time to complete
            
            % Get values and check
            Collected = get_collected_values(Table),
            ets:delete(Table),
            
            ExpectedValues = List1 ++ List2,
            lists:sort(Collected) =:= lists:sort(ExpectedValues)
        end).

prop_merge_async_only() ->    
    ?FORALL(Lists, list(list(integer())),
        begin
            % Test merging multiple observables
            Observables = [observable:bind(observable:from_list(List), operator:async()) || List <- Lists],
            MergedObs = observable:merge(Observables),

            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = merge_lists(Lists, []),

            EmittedValues =:= ExpectedValues
        end).

prop_merge_async_sync_randomly() ->    
    ?FORALL(Lists, list(list(integer())),
        begin
            % Test merging multiple observables
            Observables = [
                            case rand:uniform(2) of
                                1 -> observable:from_list(List);
                                2 -> observable:bind(observable:from_list(List), operator:async())
                            end
                            || List <- Lists
                          ],
            MergedObs = observable:merge(Observables),

            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = merge_lists(Lists, []),

            EmittedValues =:= ExpectedValues
        end).

% Test zipping sync and async observables 
prop_zip_sync_async() ->
    ?FORALL({List1, List2}, {non_empty(list(integer())), non_empty(list(integer()))},
        begin
            % Create a sync observable and an async observable
            SyncObs = observable:from_list(List1),
            AsyncObs = observable:bind(observable:from_list(List2), operator:async()),
            
            % Zip them
            ZippedObs = observable:zip([SyncObs, AsyncObs]),
            
            % Track results
            Results = ets:new(items_table, [duplicate_bag]),
            Subscriber = create_collecting_subscriber(Results),
            
            % Subscribe and wait for completion
            observable:subscribe(ZippedObs, Subscriber),
            timer:sleep(100), % Give async time to complete
            
            % Get values and check
            Collected = get_collected_values(Results),
            ets:delete(Results),
            
            MinLen = min(length(List1), length(List2)),
            Expected = [
                [lists:nth(I, List1), lists:nth(I, List2)]
                || I <- lists:seq(1, MinLen)
            ],
            
            Collected =:= Expected
        end).

% Add this new property test function:
prop_zip_random_async() ->
    ?FORALL({List1, List2, List3}, {non_empty(list(integer())), non_empty(list(integer())), non_empty(list(integer()))},
        begin
            % Randomly make some observables async
            MakeRandomAsync = fun(List) ->
                case rand:uniform(2) of
                    1 -> observable:bind(observable:from_list(List), operator:async());
                    2 -> observable:from_list(List)
                end
            end,
            
            % Create observables with random mix of sync and async
            Obs1 = MakeRandomAsync(List1),
            Obs2 = MakeRandomAsync(List2),
            Obs3 = MakeRandomAsync(List3),
            
            % Zip them
            ZippedObs = observable:zip([Obs1, Obs2, Obs3]),
            
            % Track results
            Results = ets:new(zip_random_async_test, [duplicate_bag]),
            Subscriber = create_collecting_subscriber(Results),
            
            % Subscribe and wait for completion
            observable:subscribe(ZippedObs, Subscriber),
            timer:sleep(100), % Give async time to complete
            
            % Get values and check
            Collected = get_collected_values(Results),
            ets:delete(Results),
            
            % Calculate expected results
            MinLen = lists:min([length(List1), length(List2), length(List3)]),
            Expected = [
                [lists:nth(I, List1), lists:nth(I, List2), lists:nth(I, List3)]
                || I <- lists:seq(1, MinLen)
            ],
            
            % Check results match expected values
            length(Collected) =:= length(Expected) andalso
            lists:sort(Collected) =:= lists:sort(Expected)
        end).

%%%%%%%%%%%%%%%
%%% Helpers %%%
%%%%%%%%%%%%%%%

% Creates a subscriber that collects values in an ETS table
create_collecting_subscriber(Table) ->
    subscriber:create(
        fun(Value) -> ets:insert(Table, {value, Value}) end,
        fun(Error) -> ets:insert(Table, {error, Error}) end,
        fun() -> ets:insert(Table, {complete, true}) end
    ).

% Retrieves collected values from the ETS table
get_collected_values(Table) ->
    Values = ets:match_object(Table, {value, '_'}),
    [V || {_, V} <- Values].

merge_lists([], Acc) ->  lists:reverse(Acc);
merge_lists([List | Lists], Acc) ->
    case List of
        []            -> merge_lists(Lists, Acc);
        [Elem | Rest] -> merge_lists(Lists ++ [Rest], [Elem|Acc])
    end.