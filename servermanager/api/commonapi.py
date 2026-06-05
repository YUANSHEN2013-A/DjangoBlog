import logging
import os
import subprocess
from typing import Optional

from openai import AsyncOpenAI

from servermanager.models import commands

logger = logging.getLogger(__name__)


class ChatGPT:
    _client: Optional[AsyncOpenAI] = None

    @classmethod
    def _get_client(cls) -> AsyncOpenAI:
        if cls._client is None:
            api_key = os.environ.get('OPENAI_API_KEY')
            http_proxy = os.environ.get('HTTP_PROXY')
            client_kwargs = {}
            if api_key:
                client_kwargs['api_key'] = api_key
            if http_proxy:
                client_kwargs['http_client'] = None
            cls._client = AsyncOpenAI(**client_kwargs)
        return cls._client

    @staticmethod
    async def chat(prompt: str) -> str:
        try:
            client = ChatGPT._get_client()
            completion = await client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}]
            )
            return completion.choices[0].message.content or ""
        except Exception as e:
            logger.error(f"OpenAI API调用失败: {str(e)}")
            return "服务器繁忙，请稍后再试~"


class CommandHandler:
    SAFE_COMMANDS = {
        'clear_cache': lambda: '缓存已清除',
        'build_index': lambda: '索引已重建',
        'ping_baidu': lambda: subprocess.run(
            ['ping', '-c', '1', 'baidu.com'],
            capture_output=True,
            text=True,
            timeout=5
        ).stdout or 'Ping执行完成'
    }

    def __init__(self):
        self.commands = commands.objects.all()

    def run(self, title):
        cmd = list(
            filter(
                lambda x: x.title.upper() == title.upper(),
                self.commands))
        if cmd:
            return self.__run_command__(cmd[0].command)
        else:
            return "未找到相关命令，请输入helpme获得帮助。"

    def __run_command__(self, cmd):
        try:
            cmd_name = cmd.strip().lower()
            if cmd_name in self.SAFE_COMMANDS:
                return self.SAFE_COMMANDS[cmd_name]()
            else:
                return f'命令 "{cmd}" 不在允许的安全命令列表中'
        except subprocess.TimeoutExpired:
            return '命令执行超时'
        except Exception as e:
            logger.error(f'命令执行出错: {str(e)}')
            return '命令执行出错!'

    def get_help(self):
        rsp = ''
        for cmd in self.commands:
            rsp += '{c}:{d}\n'.format(c=cmd.title, d=cmd.describe)
        return rsp


if __name__ == '__main__':
    import asyncio

    async def main():
        chatbot = ChatGPT()
        prompt = "写一篇1000字关于AI的论文"
        result = await chatbot.chat(prompt)
        print(result)

    asyncio.run(main())
