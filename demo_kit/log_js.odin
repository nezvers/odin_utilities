#+build js
package demo_kit

// The browser has no files and no environment: the log can still go to a buffer (LogToBuffer), the sinks of log_file.odin are not here.

DEMO_LOG :: ""
DEMO_LOG_KINDS :: ""

LogFromEnvironment :: proc(log: ^Log) -> bool {
    return false
}
