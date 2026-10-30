#!/usr/bin/env python3
"""Create fictional local Codex records for public native-view previews."""
import datetime as dt
import json
from pathlib import Path
import sqlite3
import sys

root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
db_path = root / "state_5.sqlite"
if db_path.exists():
    raise SystemExit("Choose a fresh output directory; an existing database will not be replaced.")
now = dt.datetime.now(dt.timezone.utc)
def stamp(offset=0):
    return (now + dt.timedelta(seconds=offset)).isoformat().replace("+00:00", "Z")
db = sqlite3.connect(db_path)
db.executescript("""
CREATE TABLE threads(id TEXT,title TEXT,name TEXT,rollout_path TEXT,updated_at INTEGER,model TEXT,tokens_used INTEGER,archived INTEGER,agent_path TEXT,thread_source TEXT,project_id TEXT,cwd TEXT,reasoning_effort TEXT);
CREATE TABLE projects(id TEXT,name TEXT,position INTEGER);
CREATE TABLE project_roots(project_id TEXT,path TEXT,position INTEGER);
INSERT INTO projects VALUES('api','Atlas API',0),('web','Web Console',1);
INSERT INTO project_roots VALUES('api','/demo/atlas',0),('web','/demo/web',0);
""")
items = [("api", "Refactor request validation", 620000, "running"),
         ("api", "Add integration coverage", 380000, "waiting"),
         ("api", "Improve error messages", 260000, "completed"),
         ("web", "Polish the settings panel", 450000, "running"),
         ("web", "Improve keyboard navigation", 190000, "completed"),
         (None, "Explore a small prototype", 100000, "completed")]
for i, (project, title, total, phase) in enumerate(items):
    session_id = f"00000000-0000-4000-8000-{i+1:012d}"
    turn = f"demo-turn-{i}"
    input_tokens = int(total * 0.92)
    usage = dict(input_tokens=input_tokens, cached_input_tokens=int(input_tokens*0.73),
                 output_tokens=total-input_tokens, reasoning_output_tokens=0, total_tokens=total)
    records = [dict(type="token_usage_record", timestamp=stamp(-120),
                    payload=dict(response_id=f"demo-response-{i}", turn_id=turn, usage=usage)),
               dict(type="event_msg", timestamp=stamp(-90), payload=dict(type="token_count",
                    info=dict(total_token_usage=usage),
                    rate_limits=dict(primary=dict(used_percent=18, window_minutes=300, resets_at=int(now.timestamp())+7200),
                                     secondary=dict(used_percent=32, window_minutes=10080, resets_at=int(now.timestamp())+172800)))),
               dict(type="event_msg", timestamp=stamp(-60), payload=dict(type="task_started", turn_id=turn))]
    # Completed previous round: deliberately distinct from conversation totals.
    previous = f"demo-previous-{i}"
    first, duration, output = [(1800,26000,420),(2100,44000,563),(1400,18000,383),
                               (3200,38000,555),(2000,21000,260),(2400,34000,420)][i]
    performance = [dict(type="event_msg",timestamp=stamp(-200),
                        payload=dict(type="task_started",turn_id=previous,root_turn_id=previous)),
                   dict(type="token_usage_record",timestamp=stamp(-180),
                        payload=dict(response_id=f"demo-metric-{i}",turn_id=previous,root_turn_id=previous,
                                     turn_token_usage=dict(output_tokens=output))),
                   dict(type="event_msg",timestamp=stamp(-170),
                        payload=dict(type="task_complete",turn_id=previous,root_turn_id=previous,
                                     duration_ms=duration,time_to_first_token_ms=first))]
    records = performance + records
    effort = ["high", "medium", "xhigh"][i % 3]
    config = dict(model="demo-model",reasoning_effort=effort)
    if i % 3 != 2:
        config["service_tier"] = "priority" if i % 3 == 0 else "default"
    # A selected running conversation demonstrates unknown mode explicitly.
    if i == 3:
        config.pop("service_tier", None)
    records.insert(0,dict(type="event_msg",timestamp=stamp(-220),
                         payload=dict(type="thread_settings_applied",thread_id=session_id,thread_settings=config)))
    if phase == "waiting":
        records.append(dict(type="event_msg", timestamp=stamp(-30), payload=dict(type="request_user_input", turn_id=turn, id="demo-question")))
    elif phase == "completed":
        fields = dict(type="task_complete",turn_id=turn,root_turn_id=turn)
        # One legacy conversation intentionally has no timing/turn usage fields.
        if i != 4:
            records.append(dict(type="token_usage_record",timestamp=stamp(-31),
                                payload=dict(response_id=f"demo-final-{i}",turn_id=turn,root_turn_id=turn,
                                             turn_token_usage=dict(output_tokens=output))))
            fields.update(duration_ms=duration,time_to_first_token_ms=first)
        records.append(dict(type="event_msg", timestamp=stamp(-30), payload=fields))
    log = root / f"demo-{i}.jsonl"
    log.write_text("".join(json.dumps(r)+"\n" for r in records))
    cwd = "/demo/atlas" if project == "api" else "/demo/web" if project else "/demo/unassigned"
    db.execute("INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", (session_id,title,None,str(log),int(now.timestamp())-i,"demo-model",total,0,None,"user",project,cwd,effort))
db.commit()
db.close()
print(root)
