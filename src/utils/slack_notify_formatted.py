import requests
from datetime import datetime

# Slack Webhook URL (適切に設定してください)
WEBHOOK_URL = "https://hooks.slack.com/services/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"

def notify_slack(symbol, timeframe, error):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    message = (
        "<@UD71EA2RE> *[MT5 Job Error]*\n"
        f"• Time: `{timestamp}`\n"
        f"• Symbol: `{symbol}`\n"
        f"• Timeframe: `{timeframe}`\n"
        f"• Error: *{error}*"
    )
    try:
        response = requests.post(WEBHOOK_URL, json={"text": message})
        if response.status_code != 200:
            print(f"[Slack Error] {response.status_code} - {response.text}")
    except Exception as e:
        print(f"[Slack Exception] {e}")