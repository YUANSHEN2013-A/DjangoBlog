import asyncio
import logging
import os
import re
import shlex
from io import StringIO

from django.core.management import call_command
from openai import AsyncOpenAI, OpenAIError

from servermanager.models import commands

logger = logging.getLogger(__name__)


class ChatGPT:
    FRIENDLY_ERROR_MESSAGE = "机器人暂时无法回复，请稍后再试。"
    MODEL = os.environ.get('OPENAI_MODEL', 'gpt-3.5-turbo')

    @classmethod
    def _get_client(cls):
        api_key = os.environ.get('OPENAI_API_KEY')
        if not api_key:
            logger.warning('OPENAI_API_KEY 未配置，无法调用 OpenAI API')
            return None

        return AsyncOpenAI(api_key=api_key)

    @staticmethod
    def _normalize_prompt(prompt):
        if prompt is None:
            return ''
        return str(prompt).strip()

    @classmethod
    async def async_chat(cls, prompt):
        message = cls._normalize_prompt(prompt)
        if not message:
            return '请输入聊天内容。'

        client = cls._get_client()
        if client is None:
            return cls.FRIENDLY_ERROR_MESSAGE

        try:
            completion = await client.chat.completions.create(
                model=cls.MODEL,
                messages=[{"role": "user", "content": message}],
            )
            content = completion.choices[0].message.content
            if isinstance(content, str) and content.strip():
                return content.strip()
            return cls.FRIENDLY_ERROR_MESSAGE
        except OpenAIError as exc:
            logger.exception('OpenAI API 调用失败: %s', exc)
            return cls.FRIENDLY_ERROR_MESSAGE
        except Exception as exc:
            logger.exception('ChatGPT 调用失败: %s', exc)
            return cls.FRIENDLY_ERROR_MESSAGE
        finally:
            close = getattr(client, 'close', None)
            if callable(close):
                await close()

    @classmethod
    def ask(cls, prompt):
        try:
            return asyncio.run(cls.async_chat(prompt))
        except RuntimeError:
            loop = asyncio.new_event_loop()
            try:
                return loop.run_until_complete(cls.async_chat(prompt))
            finally:
                loop.close()

    @classmethod
    def chat(cls, prompt):
        return cls.ask(prompt)


class CommandHandler:
    SAFE_COMMANDS = {
        'clear_cache': {'max_args': 0},
        'build_index': {'max_args': 0},
        'ping_baidu': {
            'max_args': 1,
            'allowed_args': {'all', 'article', 'tag', 'category'},
        },
    }
    COMMAND_NAME_PATTERN = re.compile(r'^[a-z_]+$')

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
            return '未找到相关命令，请输入hepme获得帮助。'

    def _split_command(self, raw_command):
        command_line = (raw_command or '').strip()
        if not command_line:
            raise ValueError('命令不能为空。')

        tokens = shlex.split(command_line)
        if len(tokens) >= 3 and tokens[0] in {'python', 'python3'} and tokens[1] == 'manage.py':
            tokens = tokens[2:]

        if not tokens:
            raise ValueError('命令不能为空。')
        return tokens

    def _validate_command(self, raw_command):
        tokens = self._split_command(raw_command)
        command_name = tokens[0].lower()
        arguments = [str(arg).strip().lower() for arg in tokens[1:]]

        if not self.COMMAND_NAME_PATTERN.fullmatch(command_name):
            raise ValueError('命令格式不合法。')

        command_config = self.SAFE_COMMANDS.get(command_name)
        if command_config is None:
            raise ValueError('该命令未被允许执行。')

        if len(arguments) > command_config['max_args']:
            raise ValueError('命令参数不合法。')

        if command_name == 'ping_baidu':
            if not arguments:
                arguments = ['all']
            if arguments[0] not in command_config['allowed_args']:
                raise ValueError('ping_baidu 仅允许以下参数: all、article、tag、category。')
        elif arguments:
            raise ValueError('该命令不接受任何参数。')

        return command_name, arguments

    def _is_safe_command(self, raw_command):
        try:
            self._validate_command(raw_command)
            return True
        except ValueError:
            return False

    def __run_command__(self, cmd):
        try:
            command_name, arguments = self._validate_command(cmd)
            output = StringIO()
            call_command(command_name, *arguments, stdout=output)
            result = output.getvalue().strip()
            return result or '命令执行完成。'
        except ValueError as exc:
            logger.warning('拒绝执行非白名单命令: %s', cmd)
            return str(exc)
        except BaseException as exc:
            logger.exception('命令执行出错: %s', exc)
            return '命令执行出错!'

    def get_help(self):
        rsp = ''
        for cmd in self.commands:
            if self._is_safe_command(cmd.command):
                rsp += '{c}:{d}\n'.format(c=cmd.title, d=cmd.describe)
        return rsp or '当前没有可执行的安全命令。'


if __name__ == '__main__':
    chatbot = ChatGPT()
    prompt = '写一篇1000字关于AI的论文'
    print(chatbot.ask(prompt))
