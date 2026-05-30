from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import json

app = FastAPI()

@app.get("/", response_class=HTMLResponse)
async def read_root(request: Request):
    headers_dict = dict(request.headers)
    # Highlight the Authorization header if present
    auth_header = headers_dict.get("authorization", "NOT PROVIDED")
    
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>API Gateway Auth Test</title>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 40px; background-color: #f5f5f5; color: #333; }}
            .container {{ background: white; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); max-width: 800px; margin: 0 auto; }}
            h1 {{ color: #2c3e50; border-bottom: 2px solid #eee; padding-bottom: 10px; }}
            .highlight {{ background-color: #e8f5e9; padding: 15px; border-left: 5px solid #4caf50; font-family: monospace; word-wrap: break-word; font-size: 14px; margin-bottom: 20px; }}
            .missing {{ background-color: #ffebee; padding: 15px; border-left: 5px solid #f44336; font-family: monospace; font-weight: bold; margin-bottom: 20px; }}
            table {{ border-collapse: collapse; width: 100%; margin-top: 20px; }}
            th, td {{ text-align: left; padding: 12px; border-bottom: 1px solid #ddd; }}
            th {{ background-color: #f8f9fa; }}
            td.key {{ font-weight: bold; width: 30%; }}
            td.value {{ font-family: monospace; font-size: 13px; color: #d63384; word-break: break-all; }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🛡️ GCP API Gateway Token Inspector</h1>
            <p>This page reflects the HTTP headers received by the backend Cloud Run service. If the Gateway is working correctly, you should see an injected Identity Token below.</p>
            
            <h2>Authorization Header Status</h2>
            {"<div class='highlight'>✅ " + auth_header + "</div>" if auth_header != "NOT PROVIDED" else "<div class='missing'>❌ " + auth_header + "</div>"}
            
            <h2>All Received Headers</h2>
            <table>
                <tr><th>Header Key</th><th>Header Value</th></tr>
                {"".join(f"<tr><td class='key'>{k}</td><td class='value'>{v}</td></tr>" for k, v in headers_dict.items())}
            </table>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)
