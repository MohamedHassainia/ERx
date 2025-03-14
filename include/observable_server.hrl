-record(state, {
    queue             :: [any()] | undefined, % Queue of items to be emitted
    buffer_size       :: integer(), % Maximum number of items in the queue
    item_producer     :: function(),  % Function that produces items
    subscribers = []  :: list(),  % List of subscribers
    inner_state = #{} :: map(), % State used by item producer
    cast_handler      :: function(),  % Function that handles cast messages
    options = #{}     :: map(), % Additional options
    interval,          % Interval time for periodic emissions
    timer_ref         % Reference to active timer
}).
