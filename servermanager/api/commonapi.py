import logging
import os
import asyncio
import shlex
import subprocess

from openai import AsyncOpenAI
import httpx

from servermanager.models import commands

logger = logging.getLogger(__name__)

def get_openai_client():
    proxy = os.environ.get('HTTP_PROXY')
    api_key = os.environ.get('OPENAI_API_KEY', 'dummy_key')
    if proxy:
        http_client = httpx.AsyncClient(proxy=proxy)
        return AsyncOpenAI(api_key=api_key, http_client=http_client)
    return AsyncOpenAI(api_key=api_key)

client = get_openai_client()


class ChatGPT:

    @staticmethod
    async def chat(prompt):
        try:
            completion = await client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}],
                timeout=30
            )
            return completion.choices[0].message.content
        except Exception as e:
            logger.error(f"OpenAI API call failed: {e}")
            return "抱歉，由于网络或服务原因，暂时无法回答您的问题，请稍后再试。"


class CommandHandler:
    def __init__(self):
        self.commands = commands.objects.all()

    def run(self, title):
        """
        运行命令
        :param title: 命令
        :return: 返回命令执行结果
        """
        cmd = list(
            filter(
                lambda x: x.title.upper() == title.upper(),
                self.commands))
        if cmd:
            return self.__run_command__(cmd[0].command)
        else:
            return "未找到相关命令，请输入hepme获得帮助。"

    def __run_command__(self, cmd):
        try:
            parts = shlex.split(cmd)
            if not parts:
                return '命令执行出错: 命令为空'

            base_cmd = parts[0]
            
            # 白名单映射机制，预定义安全命令列表
            allowed_commands = {
                'clear_cache': ['python', 'manage.py', 'clear_cache'],
                'build_index': ['python', 'manage.py', 'build_index'],
                'ping_baidu': ['ping', '-c', '4', 'baidu.com'],
            }
            
            if base_cmd not in allowed_commands:
                return f'命令执行出错: {base_cmd} 不在安全白名单中，拒绝执行！'
                
            # 严格校验参数：当前策略为不允许任何额外参数
            if len(parts) > 1:
                return f'参数校验失败: {base_cmd} 不允许携带额外参数！'
                
            safe_cmd = allowed_commands[base_cmd]
            
            # 使用 subprocess.run 安全执行，避免 shell=True 带来的命令注入漏洞
            res = subprocess.run(safe_cmd, capture_output=True, text=True, timeout=30)
            if res.returncode == 0:
                return res.stdout
            else:
                return res.stderr or '命令执行出错!'
        except subprocess.TimeoutExpired:
            return '命令执行超时!'
        except Exception as e:
            logger.error(f"Command execution failed: {e}")
            return '命令执行出错!'

    def get_help(self):
        rsp = ''
        for cmd in self.commands:
            rsp += '{c}:{d}\n'.format(c=cmd.title, d=cmd.describe)
        return rsp


if __name__ == '__main__':
    chatbot = ChatGPT()
    prompt = "写一篇100字关于AI的论文"
    print(asyncio.run(chatbot.chat(prompt)))
