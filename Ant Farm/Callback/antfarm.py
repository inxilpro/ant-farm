# Ant Farm event callback for Ansible.
#
# Ant Farm puts this file's directory on ANSIBLE_CALLBACK_PLUGINS and sets
# ANTFARM_EVENTS to a file path. Every playbook event is appended to that file
# as one JSON object per line, so Ant Farm can show the run natively while the
# normal stdout callback still writes to the terminal.
#
# It only uses the standard library and Ansible's own callback API, and does
# nothing when ANTFARM_EVENTS isn't set.

from __future__ import absolute_import, division, print_function

__metaclass__ = type

DOCUMENTATION = """
    name: antfarm
    type: notification
    short_description: Writes playbook events as JSON lines for Ant Farm
    description:
      - Appends one JSON object per event to the file named by ANTFARM_EVENTS.
"""

import json
import os
import re
import time

from ansible.plugins.callback import CallbackBase

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MAX_TEXT = 20000
PROMPT_ACTIONS = ("pause", "ansible.builtin.pause", "ansible.legacy.pause")
RESULT_KEYS = (
    ("msg", "msg"),
    ("stdout", "stdout"),
    ("stderr", "stderr"),
    ("module_stderr", "moduleStderr"),
    ("exception", "exception"),
    ("skip_reason", "skipReason"),
)


def _text(value):
    if value is None:
        return None
    if not isinstance(value, str):
        try:
            value = json.dumps(value, default=str, indent=2, sort_keys=True)
        except Exception:
            value = str(value)
    value = ANSI.sub("", value)
    if len(value) > MAX_TEXT:
        value = value[:MAX_TEXT] + "\n… (truncated)"
    return value


def _attr(obj, *names):
    # ansible-core 2.19 renamed _host/_task/_result to host/task/result.
    for name in names:
        try:
            value = getattr(obj, name)
        except Exception:
            continue
        if value is not None:
            return value
    return None


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "antfarm"
    CALLBACK_NEEDS_ENABLED = False
    CALLBACK_NEEDS_WHITELIST = False

    def __init__(self, *args, **kwargs):
        super(CallbackModule, self).__init__(*args, **kwargs)
        self._file = None
        path = os.environ.get("ANTFARM_EVENTS")
        if path:
            try:
                self._file = open(path, "a", encoding="utf-8")
            except Exception:
                self._file = None

    # MARK: Output

    def _emit(self, event, **fields):
        if self._file is None:
            return
        fields["event"] = event
        fields["time"] = time.time()
        try:
            line = json.dumps(fields, default=str, ensure_ascii=False)
            self._file.write(line + "\n")
            self._file.flush()
        except Exception:
            pass

    def _task_fields(self, task):
        role = None
        try:
            if task._role is not None:
                role = task._role.get_name()
        except Exception:
            role = None
        name = None
        try:
            name = task.get_name().strip()
        except Exception:
            name = getattr(task, "name", None)
        # get_name() puts the role in front ("role : name"); it's sent separately.
        if name and role and name.startswith(role + " : "):
            name = name[len(role) + 3:]
        return {
            "task": str(task._uuid),
            "name": name or getattr(task, "action", None) or "",
            "action": getattr(task, "action", None),
            "role": role,
        }

    def _result(self, event, result):
        host = _attr(result, "host", "_host")
        task = _attr(result, "task", "_task")
        res = _attr(result, "result", "_result") or {}
        fields = {
            "host": host.get_name() if host is not None else None,
            "task": str(task._uuid) if task is not None else None,
            "changed": bool(res.get("changed", False)),
        }

        delegated = res.get("_ansible_delegated_vars") or {}
        if delegated.get("ansible_host"):
            fields["delegatedTo"] = delegated.get("ansible_host")

        for key, name in RESULT_KEYS:
            value = res.get(key)
            if value and not (key == "exception" and str(value).startswith("(traceback unavailable)")):
                fields[name] = _text(value)
        if res.get("rc") is not None:
            try:
                fields["rc"] = int(res.get("rc"))
            except Exception:
                pass
        diffs = []
        items = res.get("results") if isinstance(res.get("results"), list) else None
        if res.get("diff"):
            diffs.append(res.get("diff"))
        if items:
            fields["items"] = len(items)
            for item in items:
                if isinstance(item, dict) and item.get("diff"):
                    diffs.append(item.get("diff"))
        if diffs:
            text = []
            for diff in diffs:
                try:
                    text.append(self._get_diff(diff))
                except Exception:
                    text.append(_text(diff))
            joined = _text("".join(t for t in text if t))
            if joined and joined.strip():
                fields["diff"] = joined

        self._emit(event, **fields)

    # MARK: Playbook

    def v2_playbook_on_start(self, playbook):
        self._emit("playbook_start", playbook=getattr(playbook, "_file_name", None))

    def v2_playbook_on_play_start(self, play):
        hosts = play.hosts
        if isinstance(hosts, (list, tuple)):
            hosts = ",".join(str(h) for h in hosts)
        self._emit(
            "play_start",
            play=str(play._uuid),
            name=(play.get_name() or "").strip(),
            pattern=str(hosts) if hosts is not None else "",
        )

    def v2_playbook_on_task_start(self, task, is_conditional):
        fields = self._task_fields(task)
        self._emit("task_start", handler=False, prompts=fields["action"] in PROMPT_ACTIONS, **fields)

    def v2_playbook_on_handler_task_start(self, task):
        fields = self._task_fields(task)
        self._emit("task_start", handler=True, prompts=fields["action"] in PROMPT_ACTIONS, **fields)

    def v2_playbook_on_vars_prompt(self, varname, *args, **kwargs):
        self._emit("vars_prompt", name=varname)

    def v2_playbook_on_no_hosts_matched(self):
        self._emit("no_hosts_matched")

    def v2_playbook_on_no_hosts_remaining(self):
        self._emit("no_hosts_remaining")

    def v2_playbook_on_stats(self, stats):
        hosts = {}
        for host in sorted(stats.processed.keys()):
            summary = stats.summarize(host)
            hosts[host] = {
                "ok": summary.get("ok", 0),
                "changed": summary.get("changed", 0),
                "failed": summary.get("failures", 0),
                "unreachable": summary.get("unreachable", 0),
                "skipped": summary.get("skipped", 0),
                "rescued": summary.get("rescued", 0),
                "ignored": summary.get("ignored", 0),
            }
        self._emit("stats", hosts=hosts)
        if self._file is not None:
            try:
                self._file.close()
            except Exception:
                pass
            self._file = None

    # MARK: Runner

    def v2_runner_on_start(self, host, task):
        self._emit("host_start", host=host.get_name(), task=str(task._uuid))

    def v2_runner_on_ok(self, result, *args, **kwargs):
        self._result("ok", result)

    def v2_runner_on_failed(self, result, ignore_errors=False, *args, **kwargs):
        self._result("ignored" if ignore_errors else "failed", result)

    def v2_runner_on_skipped(self, result, *args, **kwargs):
        self._result("skipped", result)

    def v2_runner_on_unreachable(self, result, *args, **kwargs):
        self._result("unreachable", result)

    def v2_runner_on_async_failed(self, result, *args, **kwargs):
        self._result("failed", result)
