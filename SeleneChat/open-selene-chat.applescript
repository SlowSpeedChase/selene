-- Open the newest version of SeleneChat

set appPath to "/Users/chaseeasterling/selene/SeleneChat/.build/arm64-apple-macosx/release/SeleneChat.app"
set projectPath to "/Users/chaseeasterling/selene/SeleneChat"

try
	do shell script "test -d " & quoted form of appPath
	do shell script "open " & quoted form of appPath
on error
	-- App not found, build it
	tell application "Terminal"
		activate
		do script "cd " & quoted form of projectPath & " && ./build-app.sh && open .build/arm64-apple-macosx/release/SeleneChat.app"
	end tell
end try
