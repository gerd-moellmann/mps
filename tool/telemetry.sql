-- telemetry.sql -- SQL tools for analysing telemetry output
-- $Id$
--
-- This file can be loaded into a sqlite database that has been generated by
-- the ``mpseventsql`` tool in order to provide useful views for analysing
-- the event log.
--
-- TODO: Documentation.
-- TODO: Focus on CPU/memory overhead and pause times.
-- TODO: Log clocks_per_sec so that ClockLerp and provide output in seconds.

-- TODO: Label strings all start with double quotes.  Bug in eventsql?
CREATE VIEW Address_Label AS
        SELECT address, string
        FROM EVENT_Label JOIN EVENT_Intern USING (log_serial, stringId);


-- Correlate the processor clock with the process clock by lerp
-- Note that the subselect pattern for finding the next clock is significantly
-- faster than a join in sqlite.

CREATE INDEX EVENT_EventClockSync_log_serial_time_clock
        ON EVENT_EventClockSync (log_serial, time, clock);

CREATE VIEW ClockInterval AS
        SELECT *,
               (SELECT time FROM EVENT_EventClockSync AS top
                WHERE log_serial = bot.log_serial AND time > bot.time
                ORDER BY time) AS next
        FROM EVENT_EventClockSync as bot;

CREATE VIEW ClockLerp AS
        SELECT ci.log_serial AS log_serial,
               ci.clock,
               ci.time AS time,
               next.time AS next,
               (next.time - ci.time) / (next.clock - ci.clock) AS rate
        FROM ClockInterval AS ci,
             EVENT_EventClockSync AS next
        WHERE ci.log_serial = next.log_serial AND ci.next = next.time;


-- Model Segments

CREATE INDEX EVENT_SegAlloc_log_serial_seg_time ON EVENT_SegAlloc (log_serial, seg, time);
CREATE INDEX EVENT_SegFree_log_serial_seg_time ON EVENT_SegFree (log_serial, seg, time);

CREATE VIEW Seg AS
        SELECT *,
               (SELECT time
                FROM EVENT_SegFree
                WHERE log_serial = alloc.log_serial AND
                      seg = alloc.seg AND
                      time >= alloc.time
                ORDER BY time) as free_time
        FROM EVENT_SegAlloc AS alloc;


-- Model Traces

CREATE INDEX EVENT_TraceCreate_log_serial_trace_time ON EVENT_TraceCreate (log_serial, trace, time);
CREATE INDEX EVENT_TraceDestroy_log_serial_trace_time ON EVENT_TraceDestroy (log_serial, trace, time);

CREATE VIEW Trace AS
        SELECT c.log_serial AS log_serial,
               c.trace AS trace,
               why,
               c.time AS create_time,
               (SELECT time
                FROM EVENT_TraceDestroy
                WHERE log_serial = c.log_serial AND
                      trace = c.trace AND
                      time >= c.time
                ORDER BY time
                LIMIT 1) AS destroy_time
        FROM EVENT_TraceCreate AS c;

CREATE INDEX EVENT_TraceStart_log_serial_trace_time ON EVENT_TraceStart (log_serial, trace, time);

CREATE VIEW Trace2 AS
        SELECT *
        FROM EVENT_TraceStart AS start
                LEFT JOIN Trace
                ON start.log_serial = Trace.log_serial AND
                   start.trace = Trace.trace AND
                   start.time BETWEEN create_time AND destroy_time;

CREATE VIEW Trace3 AS
        SELECT *
        FROM EVENT_TraceStart AS start
                LEFT JOIN EVENT_TraceStatCondemn as condemn
                ON condemn.log_serial = Trace.log_serial AND
                   condemn.trace = Trace.trace AND
                   condemn.time BETWEEN create_time AND destroy_time
                LEFT JOIN Trace
                ON start.log_serial = Trace.log_serial AND
                   start.trace = Trace.trace AND
                   start.time BETWEEN create_time AND destroy_time;
