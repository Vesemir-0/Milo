"""Loopback-only HTTP fixture for native --ui-preview checks; no external API calls."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import time

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        model = payload.get('model', '')
        messages = payload.get('messages', [{}])
        system = str(messages[0].get('content', ''))
        user_text = next((m.get('content', '') for m in reversed(messages) if m.get('role') == 'user' and isinstance(m.get('content'), str)), '')
        if user_text.startswith('并发检查慢'):
            time.sleep(8)
        elif user_text.startswith('并发检查快'):
            time.sleep(2)
        elif user_text.startswith('排队检查'):
            time.sleep(4)
        if 'connectivity test' in system or (len(messages) == 1 and messages[0].get('content') == 'Reply OK.'):
            content = 'OK'
        elif '帮助用户理解软件报错' in system:
            content = '可能原因：服务没有按约定返回日程 JSON。\n建议：换一个模型，或重试并检查输出上限。'
        elif model == 'return-bad-json':
            content = 'This response intentionally has no event structure.'
        else:
            content = json.dumps({'events': [
                {'title': user_text.split('：')[0] if user_text.startswith('并发检查') else '原生交互检查', 'description': '第一行正文。\n第二行需要完整保留。', 'startDate': '2026-11-19T14:00:00+08:00', 'endDate': '2026-11-19T15:00:00+08:00', 'location':'测试会议室', 'notes':['核对标题与正文编辑','核对历史重新打开']},
                {'title': '另一项安排', 'description': '切换后仍可修改。', 'dueDate':'2026-11-20T18:00:00+08:00'}
            ]}, ensure_ascii=False)
        status = 200
        result = {'choices':[{'message':{'content': content}, 'finish_reason':'stop'}], 'usage':{'prompt_tokens':45,'completion_tokens':20,'total_tokens':65}}
        if model == 'return-401': status, result = 401, {'error':{'message':'Invalid API key'}}
        elif model == 'return-parameter': status, result = 400, {'error':{'message':'Unsupported parameter: temperature','param':'temperature'}}
        elif model == 'return-timeout': status, result = 504, {'error':{'message':'Upstream timed out'}}
        body = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1',48764), Handler).serve_forever()
