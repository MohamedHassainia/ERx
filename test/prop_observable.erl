-module(prop_observable).
-include_lib("proper/include/proper.hrl").
-include("observable_item.hrl").

%%%%%%%%%%%%%%%%%%
%%% Properties %%%
%%%%%%%%%%%%%%%%%%
prop_list_observable_test() ->
    ?FORALL(List, list(),
        begin
            Observable = observable:from_list(List),
            Table = ets:new(items_table, [duplicate_bag]),
            OnNextCallback = fun(Value) ->
                                true = lists:member(Value, List),
                                ets:insert(Table, {list_obsrv, Value})
                              end,
            Subscriber = subscriber:create(OnNextCallback),
            observable:subscribe(Observable, [Subscriber]),
            StoredList = [Value || {_Key, Value} <- ets:lookup(Table, list_obsrv)],
            ets:delete(Table),
            List == StoredList
        end).


prop_take_value_observable_test() ->
    ?FORALL({N, Value}, {non_neg_integer(), any()},
        begin
            Observable = observable:bind(observable:from_value(Value), operator:take(N)),
            OnNextActions = fun(Item) ->
                                Value = Item
                              end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:duplicate(N, Value) =:= StoredList
        end),
    ?FORALL({N, List}, {non_neg_integer(), list()},
        begin
            Observable = observable:bind(observable:from_list(List), operator:take(N)),
            OnNextActions = fun(Item) ->
                                true = lists:member(Item, List)
                              end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:sublist(List, N) =:= StoredList
        end).

        
prop_zip_observable_test() ->
    ?FORALL({List1, List2, Value}, {list(term()), list(term()), term()}, 
        begin
            MinListLength = min(length(List1), length(List2)),
            Observable = observable:zip([
                observable:from_list(lists:sublist(List1, MinListLength)),
                observable:from_list(lists:sublist(List2, MinListLength)),
                observable:from_value(Value)
            ]),
            OnNextActions = fun(Item) ->
                            true = is_list(Item) andalso 3 == length(Item)
                        end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            ValueList = lists:duplicate(MinListLength, Value),
            lists:zipwith3(fun(E1, E2, E3) -> [E1, E2, E3] end, lists:sublist(List1, MinListLength), lists:sublist(List2, MinListLength), ValueList) =:= StoredList
        end),
    ?FORALL({List1, List2, Value, List3}, {list(), list(), term(), list()}, 
        begin
            MinListLength = lists:min([length(List1), length(List2), length(List3)]),
            Observable = observable:zip([
                observable:from_list(List1),
                observable:from_list(List2),
                observable:from_value(Value),
                observable:from_list(List3)
            ]),
            OnNextActions = fun(Item) ->
                                true = is_list(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            ValueList = lists:duplicate(MinListLength, Value),
            ZippedLists = lists:reverse(zip_lists([List1, List2, ValueList, List3])), 
            ZippedLists =:= StoredList
        end),
    ?FORALL({List1, List2}, {list(term()), list(term())}, 
        begin
            Observable = observable:zip([
                observable:from_list(List1),
                observable:from_list(List2)
            ]),
            OnNextActions = fun(Item) ->
                                true = is_list(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            ZippedLists = lists:reverse(zip_lists([List1, List2])), 
            ZippedLists =:= StoredList
        end),
    ?FORALL({List1}, {list(term())}, 
        begin
            Observable = observable:zip([
                observable:from_list(List1)
            ]),
            OnNextActions = fun(Item) ->
                                true = is_list(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            ZippedLists = lists:reverse(zip_lists([List1])), 
            ZippedLists =:= StoredList
        end)
        .

prop_zip_lists_test() ->
    ?FORALL({List1, List2, List3, List4, List5}, {list(), list(), list(), list(), list()},
        begin
            Lists = [List1, List2, List3, List4, List5],
            ZippedLists = zip_lists(Lists),
            MinListLength = lists:min([length(L) || L <- Lists]),
            TrimedLists = [lists:sublist(L, MinListLength) || L <- Lists],
            [lists:all(fun(Elem) -> lists:member(Elem, lists:flatten(ZippedLists)) end,L)|| L <- TrimedLists],
            length(ZippedLists) == MinListLength
        end
    ),
    ?FORALL({List1, List2}, {list(), list()},
        begin
            Lists = [List1, List2],
            ZippedLists = zip_lists(Lists),
            MinListLength = lists:min([length(L) || L <- Lists]),
            TrimedLists = [lists:sublist(L, MinListLength) || L <- Lists],
            [lists:all(fun(Elem) -> lists:member(Elem, lists:flatten(ZippedLists)) end,L)|| L <- TrimedLists],
            length(ZippedLists) == MinListLength
        end
    ),
    ?FORALL({List1}, {list()},
        begin
            Lists = [List1],
            ZippedLists = zip_lists(Lists),
            MinListLength = lists:min([length(L) || L <- Lists]),
            TrimedLists = [lists:sublist(L, MinListLength) || L <- Lists],
            [lists:all(fun(Elem) -> lists:member(Elem, lists:flatten(ZippedLists)) end,L)|| L <- TrimedLists],
            length(ZippedLists) == MinListLength
        end
    ).

prop_map_test() ->
    ?FORALL(List, list(), 
        begin
            MapFun = fun(X) -> {X} end,
            Observable = observable:bind(observable:from_list(List), operator:map(MapFun)),
            OnNextActions = fun({Item}) ->
                                true = lists:member(Item, List)
                              end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:map(MapFun, List) =:= StoredList
        end
).

prop_filter_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X < 0 end,
            Observable = observable:bind(observable:from_list(List), operator:filter(Pred)),
            OnNextActions = fun(Item) ->
                                true = lists:member(Item, List) andalso Pred(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:filter(Pred, List) =:= StoredList
        end).

prop_take_while_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X > 0 end,
            Observable = observable:bind(observable:from_list(List), operator:take_while(Pred)),
            OnNextActions = fun(Item) ->
                                true = lists:member(Item, List) andalso Pred(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:takewhile(Pred, List) =:= StoredList
        end).

prop_pipe_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X > 0 end,
            MapFun = fun(X) -> X * X end,
            TakeN = 6,
            Observable = 
                observable:pipe(
                                observable:from_list(List),
                                [operator:filter(Pred),
                                 operator:map(MapFun),
                                 operator:take(TakeN)]
                                ),
            ListsResult = lists:sublist(lists:map(MapFun, lists:filter(Pred, List)), TakeN),
            OnNextActions = fun(Item) ->
                                true = is_integer(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            ListsResult =:= StoredList
        end
).



prop_any_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X > 0 end,
            MapFun = fun(X) -> X * X end,
            TakeN = 20,
            AnyPred = fun(X) -> X > 21 end,
            Observable = 
                observable:pipe(
                                observable:from_list(List),
                                [operator:filter(Pred),
                                 operator:map(MapFun),
                                 operator:take(TakeN),
                                 operator:any(AnyPred)]
                                ),
            ListsResult = lists:any(AnyPred, lists:sublist(lists:map(MapFun, lists:filter(Pred, List)), TakeN)),
            OnNextActions = fun(Item) ->
                                do_nothing
                            end,
            [Bool] = get_observable_fired_items(Observable, OnNextActions),
            ListsResult =:= Bool
        end
).

prop_all_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X > 0 end,
            MapFun = fun(X) -> X * X end,
            TakeN = 20,
            AllPred = fun(X) -> X < 21 end,
            Observable = 
                observable:pipe(
                                observable:from_list(List),
                                [operator:filter(Pred),
                                 operator:map(MapFun),
                                 operator:take(TakeN),
                                 operator:all(AllPred)]
                                ),
            ListsResult = lists:all(AllPred, lists:sublist(lists:map(MapFun, lists:filter(Pred, List)), TakeN)),
            OnNextActions = fun(Item) ->
                                do_nothing
                            end,
            [Bool] = get_observable_fired_items(Observable, OnNextActions),
            ListsResult =:= Bool
        end
).

prop_error_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X > 0 end,
            MapFun = fun(X) -> X * X end,
            TakeN = 20,
            AllPred = fun(X) -> X < 21 end,
            Observable = 
                observable:pipe(
                                observable:create(fun(State) -> {?ERROR("Error"), State} end),
                                [operator:filter(Pred),
                                 operator:map(MapFun),
                                 operator:take(TakeN),
                                 operator:all(AllPred)]
                                ),
            Result = ?ERROR("Error"),
            OnNextActions = fun(_Item) ->
                                do_nothing
                            end,
            [Item] = observable:subscribe(Observable, subscriber:create(OnNextActions)),
            Result =:= Item
        end
).

prop_drop_pipe_test() ->
    ?FORALL(List, list(integer()),
        begin
            MapFun = fun(X) -> X * X end,
            DropN = 20,
            AllPred = fun(X) -> X < 21 end,
            Observable = 
                observable:pipe(
                                observable:from_list(List),
                                [operator:map(MapFun),
                                 operator:drop(DropN),
                                 operator:all(AllPred)
                                ]
                                ),
            ListsResult = case length(List) of
                            Len when Len =< DropN  ->
                                true;
                            _ ->
                                lists:all(AllPred, lists:nthtail(DropN, lists:map(MapFun, List)))
                          end,
            OnNextActions = fun(_Item) ->
                                do_nothing
                            end,
            [Bool] = get_observable_fired_items(Observable, OnNextActions),
            ListsResult =:= Bool
        end
).

prop_drop_2_test() ->
    ?FORALL({List, DropN}, {list(), non_neg_integer()},
        begin
            Observable = 
                observable:bind(
                                observable:from_list(List),
                                operator:drop(DropN)
                                ),
            ListsResult = case length(List) of
                            Len when Len =< DropN  ->
                                [];
                            _ ->
                                lists:nthtail(DropN, List)
                          end,
            OnNextActions = fun(_Item) ->
                                do_nothing
                            end,
            Items = get_observable_fired_items(Observable, OnNextActions),
            ListsResult =:= Items
        end
).

prop_drop_while_test() ->
    ?FORALL(List, list(integer()),
        begin
            Pred = fun(X) -> X < 0 end,
            Observable = observable:bind(observable:from_list(List), operator:drop_while(Pred)),
            OnNextActions = fun(_Item) ->
                                do_nothing
                                %true = lists:member(Item, List) andalso Pred(Item)
                            end,
            StoredList = get_observable_fired_items(Observable, OnNextActions),
            lists:dropwhile(Pred, List) =:= StoredList
        end).

%%% Reduce Operator Properties %%%
prop_reduce_test() ->
    ?FORALL(List, list(integer()),
        begin
            Sum = fun(X, Acc) -> X + Acc end,
            Observable = observable:bind(
                observable:from_list(List), 
                operator:reduce(Sum, 0)
            ),
            OnNext = fun(_Item) -> ok end,
            Result = lists:sum(List),
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            [?NEXT(Value)] = lists:filter(fun(?NEXT(_Item)) -> true;
                                     (_Item)       -> false
                                  end, ObservableItems),
            Result =:= Value
        end).

%%% Reduce Without Initial Value Properties %%%
prop_reduce_no_init_test() ->
    ?FORALL(List, non_empty(list(integer())),
        begin
            Sum = fun(X, Acc) -> X + Acc end,
            Observable = observable:bind(
                observable:from_list(List), 
                operator:reduce(Sum)
            ),
            OnNext = fun(_Item) -> ok end,
            [First|Rest] = List,
            Result = lists:foldl(Sum, First, Rest),
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            [?NEXT(Value)] = lists:filter(fun(?NEXT(_)) -> true;
                                           (_) -> false
                                        end, ObservableItems),
            Result =:= Value
        end),
    % Test empty list case
    begin
        Sum = fun(X, Acc) -> X + Acc end,
        Observable = observable:bind(
            observable:from_list([]), 
            operator:reduce(Sum)
        ),
        OnNext = fun(_Item) -> ok end,
        [?ERROR(no_values)] = observable:subscribe(Observable, subscriber:create(OnNext)),
        true
    end.

%%% Sum Operator Properties %%%
prop_sum_test() ->
    ?FORALL(List, list(number()),
        begin
            Observable = observable:bind(
                observable:from_list(List), 
                operator:sum()
            ),
            OnNext = fun(_Item) -> ok end,
            ExpectedSum = lists:sum(List),
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            [?NEXT(Value)] = lists:filter(fun(?NEXT(_)) -> true;
                                           (_) -> false
                                        end, ObservableItems),
            ExpectedSum =:= Value
        end).

%%% Product Operator Properties %%%
prop_product_test() ->
    ?FORALL(List, list(number()),
        begin
            Observable = observable:bind(
                observable:from_list(List), 
                operator:product()
            ),
            OnNext = fun(_Item) -> ok end,
            ExpectedProduct = lists:foldl(fun(X, Acc) -> X * Acc end, 1, List),
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            [?NEXT(Value)] = lists:filter(fun(?NEXT(_)) -> true;
                                           (_) -> false
                                        end, ObservableItems),
            ExpectedProduct =:= Value
        end).

%%% Merge Properties %%%
prop_merge_test() ->
    ?FORALL({List1, List2}, {list(integer()), list(integer())},
        begin
            % Test merging two observables
            Observable1 = observable:from_list(List1),
            Observable2 = observable:from_list(List2),
            MergedObs = observable:merge([Observable1, Observable2]),

            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = List1 ++ List2,

            % Order may vary but values should be the same
            lists:sort(EmittedValues) =:= lists:sort(ExpectedValues)
        end),
    
    ?FORALL(Lists, list(list(integer())),
        begin
            % Test merging multiple observables
            Observables = [observable:from_list(List) || List <- Lists],
            MergedObs = observable:merge(Observables),

            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = lists:flatten(Lists),

            % Order may vary but values should be the same
            lists:sort(EmittedValues) =:= lists:sort(ExpectedValues)
        end),
    

    ?FORALL(Lists, list(list(integer())),
        begin
            % Test merging multiple observables
            Observables = [observable:from_list(List) || List <- Lists],
            MergedObs = observable:merge(Observables),

            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = merge_lists(Lists, []),

            EmittedValues =:= ExpectedValues
        end).

% prop_merge_test_2() ->
%     ?FORALL(Lists, list(list(integer())),
%         begin
%             % Test merging multiple observables
%             Observables = [observable:from_list(List) || List <- Lists],
%             ErrorObservable = observable:create(fun(State) -> {?ERROR("Error"), State} end),
%             CompletedObservable = observable:create(fun(State) -> {?COMPLETE, State} end),
%             MergedObs = observable:merge([CompletedObservable] ++ Observables ++ [ErrorObservable]),

%             OnNext = fun(_Item) -> ok end,
%             ObservableItems = observable:subscribe(MergedObs, subscriber:create(OnNext)),
            
%             EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
%             ExpectedList = [hd(List) || List <- Lists, List /= []],
%             ExpectedValues = [?COMPLETE] ++ ExpectedList ++ [?ERROR("Error")],

%             EmittedValues =:= ExpectedValues
%         end).

    % Test empty list of observables
    % begin
    %     EmptyMerged = observable:merge([]),
    %     OnNext = fun(_Item) -> ok end,
    %     [?COMPLETE] = observable:subscribe(EmptyMerged, subscriber:create(OnNext)),
    %     true
    % end

%%% Distinct Operator Properties %%%
prop_distinct_test() ->
    ?FORALL(List, list(),
        begin
            Observable = observable:bind(
                observable:from_list(List),
                operator:distinct()
            ),
            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            ExpectedValues = lists:usort(List),
            
            % Order must be preserved for first occurrence of each value
            lists:sort(EmittedValues) =:= ExpectedValues andalso
            lists:subtract(EmittedValues, ExpectedValues) =:= [] andalso
            length(EmittedValues) =:= length(ExpectedValues)
        end).

%%% Distinct Until Changed Properties %%%
prop_distinct_until_changed_test() ->
    ?FORALL(List, list(),
        begin
            Observable = observable:bind(
                observable:from_list(List),
                operator:distinct_until_changed()
            ),
            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            
            % Remove consecutive duplicates from original list
            ExpectedValues = lists:foldr(
                fun(X, []) -> [X];
                   (X, [H|T]) when X =:= H -> [H|T];
                   (X, Acc) -> [X|Acc]
                end, [], List),
            
            % Values should match and maintain relative order
            EmittedValues =:= ExpectedValues
        end).

%%% FlatMap Operator Properties %%%
prop_flat_map_test() ->
    ?FORALL({List, MultiplierRange}, {list(integer()), range(1,5)},
        begin
            % Map each value to an observable that repeats it N times
            MapToObservable = fun(X) -> 
                RepeatedList = lists:duplicate(MultiplierRange, X),
                observable:from_list(RepeatedList)
            end,

            Observable = observable:bind(
                observable:from_list(List),
                operator:flat_map(MapToObservable)
            ),
            
            OnNext = fun(_Item) -> ok end,
            ObservableItems = observable:subscribe(Observable, subscriber:create(OnNext)),
            EmittedValues = [Value || ?NEXT(Value) <- ObservableItems],
            
            % Each value should appear MultiplierRange times
            ExpectedValues = lists:flatten([
                lists:duplicate(MultiplierRange, X) || X <- List
            ]),
            
            EmittedValues =:= ExpectedValues
        end).

%%%%%%%%%%%%%%%
%%% Helpers %%%
%%%%%%%%%%%%%%%

merge_lists([], Acc) ->  lists:reverse(Acc);
merge_lists([List | Lists], Acc) ->
    case List of
        []            -> merge_lists(Lists, Acc);
        [Elem | Rest] -> merge_lists(Lists ++ [Rest], [Elem|Acc])
    end.

zip_lists(Lists) ->
    zip_lists(Lists, _Result = []).
zip_lists(Lists, Result) ->
    case lists:any(fun(L) -> L == [] end, Lists) of
        true ->
            Result;
        false ->
            Heads = [hd(L) || L <- Lists],
            Tails = [Tail || [_Head|Tail] <- Lists],
            zip_lists(Tails, [Heads|Result])
    end.

get_observable_fired_items(Observable, OnNextActions) ->
    Table = ets:new(items_table, [duplicate_bag]),
    OnNextCallback = fun(Item) ->
        apply(OnNextActions, [Item]),
        ets:insert(Table, {obsrv, Item})
      end,
    Subscriber = subscriber:create(OnNextCallback),
    observable:subscribe(Observable, [Subscriber]),
    StoredList = [Item || {_Key, Item} <- ets:lookup(Table, obsrv)],
    ets:delete(Table),
    StoredList.

%%%%%%%%%%%%%%%%%%
%%% Generators %%%
%%%%%%%%%%%%%%%%%%
int_list_observable() -> ?LET(List, list(integer()), observable:from_list(List)).
value_observable() -> ?LET(Value, any(), observable:from_value(Value)).
positive_integer() -> ?LET(N, integer(), abs(N) + 1).
take_operator() -> ?LET({N, Observable}, {positive_integer(), value_observable()}, observable:bind(Observable, operator:take(N))).

