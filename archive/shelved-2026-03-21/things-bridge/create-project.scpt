#!/usr/bin/osascript
-- create-project.scpt
-- Creates a project in Things 3 from a JSON file
--
-- Usage: osascript create-project.scpt /path/to/project.json
--
-- JSON format:
-- {
--   "name": "Project name",           -- required
--   "notes": "Project description",   -- optional
--   "area": "Area name"               -- optional
-- }
--
-- Returns: The Things project ID on success, or error message on failure

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
        -- Extract name (required)
        set projectName to do shell script jqPath & " -r '.name // empty' " & quoted form of jsonFilePath
        if projectName is "" then
            return "ERROR: Missing required field 'name' in JSON"
        end if

        -- Extract notes (optional, default empty)
        set projectNotes to do shell script jqPath & " -r '.notes // \"\"' " & quoted form of jsonFilePath

        -- Extract area (optional)
        set areaName to do shell script jqPath & " -r '.area // empty' " & quoted form of jsonFilePath

    on error errMsg
        return "ERROR: Failed to parse JSON: " & errMsg
    end try

    -- Create the project in Things 3
    try
        tell application "Things3"
            -- Create new project
            if areaName is "" then
                set newProject to make new project with properties {name:projectName, notes:projectNotes}
            else
                -- Try to find the area
                try
                    set targetArea to area areaName
                    set newProject to make new project with properties {name:projectName, notes:projectNotes, area:targetArea}
                on error
                    -- Area not found, create project without area
                    set newProject to make new project with properties {name:projectName, notes:projectNotes}
                end try
            end if

            -- Return the project ID
            return id of newProject
        end tell
    on error errMsg
        return "ERROR: Failed to create project in Things: " & errMsg
    end try
end run
