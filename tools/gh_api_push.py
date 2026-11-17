#!/usr/bin/env python3
"""Push the current HEAD to GitHub through the REST API.

github.com is unreachable from this machine (TLS reset), api.github.com is fine.
Instead of git-push we upload blobs, build a tree on top of the remote head and
create a commit with the exact same author/committer/metadata as the local one,
so the resulting SHA matches local HEAD.

  TOKEN=... python3 tools/gh_api_push.py
"""
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REPO = "emfox/tv-quiz"
BRANCH = "main"
PROXY = os.environ.get("GH_PROXY", "http://127.0.0.1:7890")
TOKEN = os.environ.get("TOKEN") or os.environ.get("GH_TOKEN")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*args, binary=False):
    out = subprocess.run(["git", "-C", ROOT] + list(args),
                         capture_output=True, check=True).stdout
    return out if binary else out.decode().strip()


def api(method, path, payload=None, raw=False):
    url = "https://api.github.com" + path
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}))
    try:
        with opener.open(req, timeout=60) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        sys.exit("%s %s -> %s\n%s" % (method, path, e.code, e.read().decode()[:600]))
    return body if raw else json.loads(body)


def ident():
    """author/committer of local HEAD; the API wants ISO 8601 dates."""
    return {
        "author": {"name": git("log", "-1", "--format=%an"),
                   "email": git("log", "-1", "--format=%ae"),
                   "date": git("log", "-1", "--format=%aI")},
        "committer": {"name": git("log", "-1", "--format=%cn"),
                      "email": git("log", "-1", "--format=%ce"),
                      "date": git("log", "-1", "--format=%cI")},
    }


def main():
    if not TOKEN:
        sys.exit("need TOKEN env (and api.github.com reachable through GH_PROXY)")

    head = git("rev-parse", "HEAD")
    parent = git("rev-parse", "HEAD~1")
    message = git("log", "-1", "--format=%B").rstrip() + "\n"

    ref = api("GET", "/repos/%s/git/ref/heads/%s" % (REPO, BRANCH))
    remote_sha = ref["object"]["sha"]
    if remote_sha == head:
        print("remote already at", head)
        return
    if remote_sha != parent:
        sys.exit("remote is %s but local parent is %s; refusing to build a tree"
                 % (remote_sha[:12], parent[:12]))

    base_tree = api("GET", "/repos/%s/git/commits/%s" % (REPO, remote_sha))["tree"]["sha"]
    print("remote %s  base tree %s" % (remote_sha[:12], base_tree[:12]))

    changed = git("diff", "--name-status", parent, head).splitlines()
    entries = []
    for line in changed:
        status, path = line.split("\t", 1)
        if status.startswith("D"):
            entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
            print("  delete", path)
            continue
        blob = git("show", "%s:%s" % (head, path), binary=True)
        sha = api("POST", "/repos/%s/git/blobs" % REPO,
                  {"content": base64.b64encode(blob).decode(), "encoding": "base64"})["sha"]
        mode = "100755" if os.access(os.path.join(ROOT, path), os.X_OK) else "100644"
        entries.append({"path": path, "mode": mode, "type": "blob", "sha": sha})
        print("  %s %s %s" % ("create" if status.startswith("A") else "update", path, sha[:8]))

    tree = api("POST", "/repos/%s/git/trees" % REPO,
               {"base_tree": base_tree, "tree": entries})["sha"]
    print("new tree", tree[:12], "(local %s)" % git("rev-parse", "HEAD^{tree}")[:12])

    who = ident()
    commit = api("POST", "/repos/%s/git/commits" % REPO, {
        "message": message, "tree": tree, "parents": [remote_sha],
        "author": who["author"], "committer": who["committer"],
    })["sha"]
    print("new commit", commit[:12], "(local %s)" % head[:12])

    api("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH),
        {"sha": commit, "force": False})
    print("done:", "identical" if commit == head else "SHA differs, check tree/mode")


if __name__ == "__main__":
    main()
