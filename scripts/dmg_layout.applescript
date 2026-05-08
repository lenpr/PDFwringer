tell application "Finder"
	tell disk "PDFwringer"
		open
		delay 1
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set bounds of container window to {200, 200, 720, 470}
		set theViewOptions to icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to 96
		set text size of theViewOptions to 13
		try
			set position of item "PDFwringer.app" of container window to {130, 130}
		end try
		try
			set position of item "Applications" of container window to {390, 130}
		end try
		update without registering applications
		delay 0.5
		close
	end tell
end tell
