#!/bin/zsh
# Сборка + установка в /Applications + автозапуск: ./install.sh
set -e
cd "$(dirname "$0")"

LABEL="com.myami.notchpanel"
DEST="/Applications/Notch Panel.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM=$(id -u)

./build.sh

# Останавливаем текущую копию (и службу, и вручную запущенную).
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
pkill -x NotchPanel 2>/dev/null || true
sleep 0.5

# Ставим в «Программы».
rm -rf "$DEST"
ditto build/NotchPanel.app "$DEST"
echo "Установлено: $DEST"

# Служба автозапуска: старт при входе, перезапуск только после сбоя (закрытие кнопкой ⏻ — не перезапускаем).
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST/Contents/MacOS/NotchPanel</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>ThrottleInterval</key>
    <integer>5</integer>
</dict>
</plist>
PLIST
echo "Автозапуск: $AGENT"

launchctl bootstrap "gui/$UID_NUM" "$AGENT"
echo "Запущено."
