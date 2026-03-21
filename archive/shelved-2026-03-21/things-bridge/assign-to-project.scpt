#!/usr/bin/osascript
-- assign-to-project.scpt
-- Moves a task to a project in Things 3
--
-- Usage: osascript assign-to-project.scpt <task_id> <project_id>
--
-- Arguments:
--   task_id    - The Things ID of the task to move
--   project_id - The Things ID of the target project
--
-- Returns: "SUCCESS" on success, or error message on failure

on run argv
    -- Validate arguments
    if (count of argv) < 2 then
        return "ERROR: Missing arguments. Usage: assign-to-project.scpt <task_id> <project_id>"
    end if

    set taskId to item 1 of argv
    set projectId to item 2 of argv

    -- Validate IDs are not empty
    if taskId is "" then
        return "ERROR: task_id cannot be empty"
    end if
    if projectId is "" then
        return "ERROR: project_id cannot be empty"
    end if

    -- Move task to project in Things 3
    try
        tell application "Things3"
            -- Find the task by ID
            set targetTask to to do id taskId

            -- Find the project by ID
            set targetProject to project id projectId

            -- Move task to project
            move targetTask to targetProject

            return "SUCCESS"
        end tell
    on error errMsg
        return "ERROR: Failed to assign task to project: " & errMsg
    end try
end run
