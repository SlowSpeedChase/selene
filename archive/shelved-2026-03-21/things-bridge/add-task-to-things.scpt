#!/usr/bin/osascript
-- add-task-to-things.scpt
-- Creates a task in Things 3 from a JSON file
--
-- Usage: osascript add-task-to-things.scpt /path/to/task.json
--
-- JSON format:
-- {
--   "title": "Task title",          -- required
--   "notes": "Task description",    -- optional
--   "tags": ["tag1", "tag2"],       -- optional
--   "project": "Project Name",      -- optional: assign to this project/area
--   "heading": "Heading Name"       -- optional: documented in notes (AppleScript limitation)
-- }
--
-- Returns: The Things task ID on success, or error message on failure

on run argv
    -- Validate argument
    if (count of argv) < 1 then
        return "ERROR: Missing JSON file path argument"
    end if

    set jsonFilePath to item 1 of argv

    -- Check if file exists
    try
        do shell script "test -f " & quoted form of jsonFilePath
    on error
        return "ERROR: File not found: " & jsonFilePath
    end try

    -- Path to jq (try multiple locations)
    set jqPath to ""
    try
        do shell script "test -x /usr/bin/jq"
        set jqPath to "/usr/bin/jq"
    end try
    if jqPath is "" then
        try
            do shell script "test -x /opt/homebrew/bin/jq"
            set jqPath to "/opt/homebrew/bin/jq"
        end try
    end if
    if jqPath is "" then
        try
            do shell script "test -x /usr/local/bin/jq"
            set jqPath to "/usr/local/bin/jq"
        end try
    end if

    -- Check if jq was found
    if jqPath is "" then
        return "ERROR: jq not found in /usr/bin, /opt/homebrew/bin, or /usr/local/bin"
    end if

    -- Read and parse JSON fields
    try
        -- Extract title (required)
        set taskTitle to do shell script jqPath & " -r '.title // empty' " & quoted form of jsonFilePath
        if taskTitle is "" then
            return "ERROR: Missing required field 'title' in JSON"
        end if

        -- Extract notes (optional, default empty)
        set taskNotes to do shell script jqPath & " -r '.notes // \"\"' " & quoted form of jsonFilePath

        -- Extract tags as comma-separated string (optional)
        -- jq outputs each tag on a line, we join them
        set tagsList to do shell script jqPath & " -r '.tags // [] | .[]' " & quoted form of jsonFilePath

        -- Extract project name (optional)
        set projectName to do shell script jqPath & " -r '.project // \"\"' " & quoted form of jsonFilePath

        -- Extract heading name (optional)
        set headingName to do shell script jqPath & " -r '.heading // \"\"' " & quoted form of jsonFilePath

    on error errMsg
        return "ERROR: Failed to parse JSON: " & errMsg
    end try

    -- Convert tags string to AppleScript list
    set AppleScript's text item delimiters to linefeed
    if tagsList is "" then
        set tagsArray to {}
    else
        set tagsArray to text items of tagsList
    end if
    set AppleScript's text item delimiters to ""

    -- Create the task in Things 3
    try
        tell application "Things3"
            -- Create new to-do (initially in inbox)
            set newToDo to make new to do with properties {name:taskTitle, notes:taskNotes}

            -- Move to project if specified
            if projectName is not "" then
                try
                    -- Try to find the project by name
                    set targetProject to project projectName
                    move newToDo to targetProject
                on error
                    -- Project not found, try as an area
                    try
                        set targetArea to area projectName
                        move newToDo to targetArea
                    on error
                        -- Neither project nor area found - stays in inbox
                        -- Add note about missing project
                        set notes of newToDo to taskNotes & linefeed & linefeed & "[Note: Project '" & projectName & "' not found in Things]"
                    end try
                end try
            end if

            -- Document heading in notes (Things 3 AppleScript doesn't support headings directly)
            if headingName is not "" then
                set notes of newToDo to notes of newToDo & linefeed & "[Heading: " & headingName & "]"
            end if

            -- Add tags if any
            repeat with tagName in tagsArray
                try
                    -- Try to add existing tag
                    set tag of newToDo to tag of newToDo & {tag tagName}
                on error
                    -- Tag doesn't exist, create it first
                    try
                        make new tag with properties {name:tagName}
                        set tag of newToDo to tag of newToDo & {tag tagName}
                    end try
                end try
            end repeat

            -- Return the task ID
            return id of newToDo
        end tell
    on error errMsg
        return "ERROR: Failed to create task in Things: " & errMsg
    end try
end run
