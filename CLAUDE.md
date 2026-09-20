Create a complete macOS Menu Bar Extra app in the current folder using SwiftUI.

Requirements:

1. Display style in the menu bar (exactly this compact format):
   [Claude icon] 5h 0% ▯▯▯▯  W 64% ▮▮▮▯  F 80% ▮▮▮▮

2. Real data source:
   - Fetch usage from Anthropic’s unofficial endpoint:
     GET https://api.anthropic.com/api/oauth/usage
   - Headers:
     Authorization: Bearer <token>
     anthropic-beta: oauth-2025-04-20
   - Get the OAuth token from ~/.claude/.credentials.json (Claude Code credentials)
   - Map:
     - five_hour.utilization → 5h
     - seven_day.utilization → W
     - seven_day_sonnet.utilization (fallback to seven_day) → F

3. Features:
   - Auto-refresh every 3 minutes
   - Manual “Refresh Now” button
   - Show error messages if token is missing or expired
   - Dropdown menu with detailed progress bars + reset time
   - No Dock icon (LSUIElement = true)
   - Clean, native macOS look

4. Project structure:
   - App.swift
   - Service.swift
   - Views.swift

5. StatusLabelView should use this exact compact design:
   - Claude icon (template image)
   - “5h XX%” + 5-block progress (▮ and ▯)
   - “W XX%” + 5-block progress
   - “F XX%” + 5-block progress
   - Rounded design font, monospaced digits, tight spacing

6. Include clear step-by-step setup instructions at the end (how to create the Xcode project, add the icon, set LSUIElement, login to Claude Code, etc.).

Please generate the full final code for all three files + setup guide.