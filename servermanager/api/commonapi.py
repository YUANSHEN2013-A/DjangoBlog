import logging
import os

import httpx
from openai import OpenAI, AsyncOpenAI

from servermanager.models import commands

logger = logging.getLogger(__name__)


def _get_openai_client():
    kwargs = {}
    api_key = os.environ.get('OPENAI_API_KEY')
    if api_key:
        kwargs['api_key'] = api_key
    proxy_url = os.environ.get('HTTP_PROXY')
    if proxy_url:
        kwargs['http_client'] = httpx.Client(proxy=proxy_url)
    return OpenAI(**kwargs)


def _get_async_openai_client():
    kwargs = {}
    api_key = os.environ.get('OPENAI_API_KEY')
    if api_key:
        kwargs['api_key'] = api_key
    proxy_url = os.environ.get('HTTP_PROXY')
    if proxy_url:
        kwargs['http_client'] = httpx.AsyncClient(proxy=proxy_url)
    return AsyncOpenAI(**kwargs)


SAFE_COMMANDS = {}


def _register_safe_commands():
    SAFE_COMMANDS.update({
        'clear_cache': _clear_cache,
        'build_index': _rebuild_index,
        'ping_baidu': _ping_baidu,
    })


def _clear_cache():
    from django.core.cache import cache
    cache.clear()
    return "缓存已清除"


def _rebuild_index():
    from django.core.management import call_command
    call_command('rebuild_index', interactive=False)
    return "索引重建完成"


def _ping_baidu():
    from blog.models import Article
    try:
        articles = Article.objects.filter(status='p')
        urls = [article.get_full_url() for article in articles]
        if urls:
            import requests
            api = 'http://data.zz.baidu.com/urls?site=&token='
            headers = {'Content-Type': 'text/plain'}
            response = requests.post(
                api,
                data='\n'.join(urls),
                headers=headers,
                timeout=10
            )
            logger.info(f"百度ping结果: {response.text}")
            return f"百度ping完成，提交{len(urls)}条URL"
        return "没有可提交的URL"
    except Exception as e:
        logger.error(f"百度ping失败: {e}")
        return f"百度ping失败: {str(e)}"


_register_safe_commands()


class ChatGPT:

    @staticmethod
    def chat(prompt):
        try:
            client = _get_openai_client()
            completion = client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}]
            )
            return completion.choices[0].message.content
        except Exception as e:
            logger.error(f"OpenAI API调用失败: {e}")
            return "服务器出错了，请稍后再试"

    @staticmethod
    async def achat(prompt):
        try:
            client = _get_async_openai_client()
            completion = await client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}]
            )
            return completion.choices[0].message.content
        except Exception as e:
            logger.error(f"OpenAI API调用失败: {e}")
            return "服务器出错了，请稍后再试"


class CommandHandler:
    def __init__(self):
        self.commands = commands.objects.all()

    def run(self, title):
        cmd = list(
            filter(
                lambda x: x.title.upper() == title.upper(),
                self.commands))
        if cmd:
            return self.__run_command__(cmd[0])
        else:
            return "未找到相关命令，请输入helpme获得帮助。"

    def __run_command__(self, cmd):
        title_lower = cmd.title.lower()
        if title_lower in SAFE_COMMANDS:
            try:
                return SAFE_COMMANDS[title_lower]()
            except Exception as e:
                logger.error(f"命令执行失败 [{cmd.title}]: {e}")
                return f"命令执行出错: {str(e)}"
        else:
            logger.warning(f"拒绝执行不在白名单中的命令: {cmd.title}")
            return f"命令 '{cmd.title}' 不在允许执行的白名单中"

    def get_help(self):
        rsp = ''
        for cmd in self.commands:
            rsp += '{c}:{d}\n'.format(c=cmd.title, d=cmd.describe)
        return rsp


if __name__ == '__main__':
    chatbot = ChatGPT()
    prompt = "写一篇1000字关于AI的论文"
    print(chatbot.chat(prompt))