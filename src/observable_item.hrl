-ifndef(OBSERVABLE_ITEM_HRL).
-define(OBSERVABLE_ITEM_HRL, true).

-type observable_item(A, ErrorInfo) :: {next, A} | {error, ErrorInfo} | complete | ignore | halt | {last, A}.

-define(NEXT(Value), {next, Value}).
-define(ERROR(ErrorInfo), {error, ErrorInfo}).
-define(COMPLETE, complete).
-define(IGNORE, ignore).
-define(HALT, halt).
-define(LAST(Value), {last, Value}).

-endif.