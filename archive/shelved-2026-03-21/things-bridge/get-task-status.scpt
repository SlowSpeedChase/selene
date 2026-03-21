#!/usr/bin/osascript
-- get-task-status.scpt
-- Gets the status of a task from Things 3 by its ID
--
-- Usage: osascript get-task-status.scpt <task_id>
--
-- Arguments:
--   task_id - The Things ID of the task to check
--
-- Returns JSON format:
-- {
--   "id": "<task_id>",
--   "status": "open|completed|canceled",
--   "name": "Task title",
--   "completion_date": "2025-01-01" or null,
--   "modification_date": "2025-01-01",
--   "creation_date": "2025-01-01",
--   "project": "Project name" or null,
--   "area": "Area name" or null,
--   "tags": ["tag1", "tag2"]
-- }
--
-- Or error format:
-- {"error": "error message"}

on run argv
    -- Validate argument
    if (count of argv) < 1 then
        return "{\"error\": \"Missing task_id argument\"}"
    end if

    set taskId to item 1 of argv

    -- Validate ID is not empty
    if taskId is "" then
        return "{\"error\": \"task_id cannot be empty\"}"
    end if

    -- Query Things 3 for task status
    try
        tell application "Things3"
            -- Find the task by ID
            set targetTask to to do id taskId

            -- Get basic properties
            set taskName to name of targetTask
            set taskStatus to status of targetTask as string
            set taskCreationDate to creation date of targetTask
            set taskModificationDate to modification date of targetTask

            -- Get completion date (may not exist)
            set taskCompletionDate to "null"
            if taskStatus is "completed" then
                try
                    set completionDateObj to completion date of targetTask
                    if completionDateObj is not missing value then
                        set taskCompletionDate to "\"" & my formatDate(completionDateObj) & "\""
                    end if
                end try
            end if

            -- Get project (may not exist)
            set taskProject to "null"
            try
                set projectObj to project of targetTask
                if projectObj is not missing value then
                    set taskProject to "\"" & name of projectObj & "\""
                end if
            end try

            -- Get area (may not exist)
            set taskArea to "null"
            try
                set areaObj to area of targetTask
                if areaObj is not missing value then
                    set taskArea to "\"" & name of areaObj & "\""
                end if
            end try

            -- Get tags
            set taskTags to "[]"
            try
                set tagObjs to tags of targetTask
                if (count of tagObjs) > 0 then
                    set tagNames to {}
                    repeat with aTag in tagObjs
                        set end of tagNames to "\"" & name of aTag & "\""
                    end repeat
                    set AppleScript's text item delimiters to ", "
                    set taskTags to "[" & (tagNames as string) & "]"
                    set AppleScript's text item delimiters to ""
                end if
            end try

            -- Build JSON response
            set jsonResponse to "{"
            set jsonResponse to jsonResponse & "\"id\": \"" & taskId & "\", "
            set jsonResponse to jsonResponse & "\"status\": \"" & taskStatus & "\", "
            set jsonResponse to jsonResponse & "\"name\": \"" & my escapeJSON(taskName) & "\", "
            set jsonResponse to jsonResponse & "\"completion_date\": " & taskCompletionDate & ", "
            set jsonResponse to jsonResponse & "\"modification_date\": \"" & my formatDate(taskModificationDate) & "\", "
            set jsonResponse to jsonResponse & "\"creation_date\": \"" & my formatDate(taskCreationDate) & "\", "
            set jsonResponse to jsonResponse & "\"project\": " & taskProject & ", "
            set jsonResponse to jsonResponse & "\"area\": " & taskArea & ", "
            set jsonResponse to jsonResponse & "\"tags\": " & taskTags
            set jsonResponse to jsonResponse & "}"

            return jsonResponse
        end tell
    on error errMsg
        -- Check if task was not found
        if errMsg contains "Can't get to do id" then
            return "{\"error\": \"Task not found: " & taskId & "\"}"
        else
            return "{\"error\": \"" & my escapeJSON(errMsg) & "\"}"
        end if
    end try
end run

-- Format date as YYYY-MM-DD
on formatDate(theDate)
    set y to year of theDate as string
    set m to (month of theDate as integer) as string
    if length of m < 2 then set m to "0" & m
    set d to day of theDate as string
    if length of d < 2 then set d to "0" & d
    return y & "-" & m & "-" & d
end formatDate

-- Escape special characters for JSON
on escapeJSON(theText)
    set resultText to ""
    repeat with i from 1 to length of theText
        set c to character i of theText
        if c is "\"" then
            set resultText to resultText & "\\\""
        else if c is "\\" then
            set resultText to resultText & "\\\\"
        else if c is (ASCII character 10) then
            set resultText to resultText & "\\n"
        else if c is (ASCII character 13) then
            set resultText to resultText & "\\r"
        else if c is (ASCII character 9) then
            set resultText to resultText & "\\t"
        else
            set resultText to resultText & c
        end if
    end repeat
    return resultText
end escapeJSON
