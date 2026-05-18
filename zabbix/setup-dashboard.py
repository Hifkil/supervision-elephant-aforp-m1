#!/usr/bin/env python3
"""Create or update the Artemis Zabbix dashboard."""

import json
import sys
import urllib.request

API = "http://localhost:8080/api_jsonrpc.php"
USER = "Admin"
PASS = "zabbix"


def call(method, params, auth=None):
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 1}
    if auth:
        payload["auth"] = auth

    req = urllib.request.Request(
        API,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as response:
        result = json.load(response)

    if "error" in result:
        raise RuntimeError(f"{method}: {result['error']}")
    return result["result"]


def field(field_type, name, value):
    return {"type": field_type, "name": name, "value": str(value)}


def reference(value):
    return field(1, "reference", value)


def item_widget(name, x, y, itemid, description, ref):
    return {
        "type": "item",
        "name": name,
        "x": x,
        "y": y,
        "width": 18,
        "height": 3,
        "view_mode": 1,
        "fields": [
            field(4, "itemid.0", itemid),
            field(0, "show.0", 1),
            field(0, "show.1", 2),
            field(1, "description", description),
            reference(ref),
        ],
    }


def graph_widget(name, x, y, series, ref):
    fields = []
    for index, serie in enumerate(series):
        fields.extend(
            [
                field(1, f"ds.{index}.hosts.0", serie["host"]),
                field(1, f"ds.{index}.items.0", serie["item"]),
                field(1, f"ds.{index}.color", serie["color"]),
                field(0, f"ds.{index}.width", 2),
                field(0, f"ds.{index}.transparency", 0),
                field(0, f"ds.{index}.fill", 0),
            ]
        )

    fields.extend(
        [
            field(0, "show_problems", 1),
            field(0, "legend", 1),
            field(0, "righty", 0),
            field(1, "time_period.from", "now-1h"),
            field(1, "time_period.to", "now"),
            reference(ref),
        ]
    )

    return {
        "type": "svggraph",
        "name": name,
        "x": x,
        "y": y,
        "width": 36,
        "height": 6,
        "view_mode": 0,
        "fields": fields,
    }


def main():
    token = call("user.login", {"username": USER, "password": PASS})
    host_names = [
        "artzab01p",
        "artdb01p",
        "artzabweb01p",
        "arthpx01p",
        "artweb01p",
        "artweb02p",
        "artbdd01p",
        "artbdd02p",
        "artsft02p",
        "artnfs01p",
        "artbkp01p",
        "artbbx01p",
        "artmet01p",
        "artprom01p",
        "artgrf01p",
        "artnag01p",
    ]
    hosts = call(
        "host.get",
        {"filter": {"host": host_names}, "output": ["hostid", "host"]},
        token,
    )
    hostids = {host["host"]: host["hostid"] for host in hosts}
    missing = [host for host in host_names if host not in hostids]
    if missing:
        raise RuntimeError(f"Missing Zabbix hosts: {', '.join(missing)}")

    def itemid(host, key):
        items = call(
            "item.get",
            {
                "hostids": [hostids[host]],
                "filter": {"key_": [key]},
                "output": ["itemid"],
            },
            token,
        )
        if not items:
            raise RuntimeError(f"Missing item {host}:{key}")
        return items[0]["itemid"]

    host_fields = [
        field(3, f"hostids.{index}", hostids[host])
        for index, host in enumerate(host_names)
    ]

    widgets = [
        {
            "type": "problems",
            "name": "Current Artemis problems",
            "x": 0,
            "y": 0,
            "width": 48,
            "height": 5,
            "view_mode": 0,
            "fields": host_fields
            + [field(0, "show", 3), field(0, "show_tags", 3), reference("ARTPR")],
        },
        {
            "type": "hostavail",
            "name": "Agent availability",
            "x": 48,
            "y": 0,
            "width": 24,
            "height": 5,
            "view_mode": 0,
            "fields": host_fields + [field(0, "interface_type.0", 1)],
        },
        item_widget(
            "HAProxy stats endpoint",
            0,
            5,
            itemid(
                "arthpx01p",
                'net.tcp.service["{$HAPROXY.STATS.SCHEME}","{$HAPROXY.STATS.HOST}","{$HAPROXY.STATS.PORT}"]',
            ),
            "arthpx01p:8406 status",
            "ART01",
        ),
        item_widget("artweb01p agent", 18, 5, itemid("artweb01p", "agent.ping"), "Zabbix agent ping", "ART02"),
        item_widget("artweb02p agent", 36, 5, itemid("artweb02p", "agent.ping"), "Zabbix agent ping", "ART03"),
        item_widget("artzab01p agent", 54, 5, itemid("artzab01p", "agent.ping"), "Zabbix agent ping", "ART04"),
        graph_widget(
            "HAProxy frontend requests and sessions",
            0,
            8,
            [
                {"host": "arthpx01p", "item": "Frontend http_front: Requests rate", "color": "29B6F6"},
                {"host": "arthpx01p", "item": "Frontend http_front: Sessions rate", "color": "66BB6A"},
                {"host": "arthpx01p", "item": "Frontend http_front: Request errors per second", "color": "EF5350"},
            ],
            "ART05",
        ),
        graph_widget(
            "HAProxy traffic",
            36,
            8,
            [
                {"host": "arthpx01p", "item": "Frontend http_front: Incoming traffic", "color": "42A5F5"},
                {"host": "arthpx01p", "item": "Frontend http_front: Outgoing traffic", "color": "FFA726"},
            ],
            "ART06",
        ),
        graph_widget(
            "Backend responses",
            0,
            14,
            [
                {"host": "arthpx01p", "item": "Backend nginx_backends: Number of responses with codes 2xx per second", "color": "66BB6A"},
                {"host": "arthpx01p", "item": "Backend nginx_backends: Number of responses with codes 4xx per second", "color": "FFCA28"},
                {"host": "arthpx01p", "item": "Backend nginx_backends: Number of responses with codes 5xx per second", "color": "EF5350"},
            ],
            "ART07",
        ),
        graph_widget(
            "Web backend CPU utilization",
            36,
            14,
            [
                {"host": "artweb01p", "item": "CPU utilization", "color": "42A5F5"},
                {"host": "artweb02p", "item": "CPU utilization", "color": "FFA726"},
            ],
            "ART08",
        ),
        item_widget(
            "DB primary TCP",
            0,
            20,
            itemid("artbdd01p", "net.tcp.service[tcp,,5432]"),
            "PostgreSQL primary port",
            "ART09",
        ),
        item_widget(
            "DB replica TCP",
            18,
            20,
            itemid("artbdd02p", "net.tcp.service[tcp,,5432]"),
            "PostgreSQL replica port",
            "ART10",
        ),
        item_widget(
            "SFTP TCP",
            36,
            20,
            itemid("artsft02p", "net.tcp.service[ssh,,22]"),
            "SFTP SSH port",
            "ART11",
        ),
        item_widget(
            "NFS TCP",
            54,
            20,
            itemid("artnfs01p", "net.tcp.service[tcp,,2049]"),
            "NFS service port",
            "ART12",
        ),
        item_widget(
            "Backup metrics",
            0,
            23,
            itemid("artbkp01p", "net.tcp.service[http,,8080]"),
            "Backup exporter HTTP",
            "ART13",
        ),
        item_widget(
            "Prometheus",
            18,
            23,
            itemid("artprom01p", "net.tcp.service[http,,9090]"),
            "Prometheus HTTP",
            "ART14",
        ),
        item_widget(
            "Grafana",
            36,
            23,
            itemid("artgrf01p", "net.tcp.service[http,,3000]"),
            "Grafana HTTP",
            "ART15",
        ),
        item_widget(
            "Nagios",
            54,
            23,
            itemid("artnag01p", "net.tcp.service[http,,80]"),
            "Nagios HTTP",
            "ART16",
        ),
        item_widget(
            "Zabbix server",
            0,
            26,
            itemid("artzab01p", "net.tcp.service[tcp,,10051]"),
            "Zabbix server trapper port",
            "ART17",
        ),
        item_widget(
            "Zabbix web",
            18,
            26,
            itemid("artzabweb01p", "net.tcp.service[http,,8080]"),
            "Zabbix web HTTP",
            "ART18",
        ),
        item_widget(
            "Blackbox exporter",
            36,
            26,
            itemid("artbbx01p", "net.tcp.service[tcp,,9115]"),
            "Blackbox exporter port",
            "ART19",
        ),
        item_widget(
            "Docker metrics",
            54,
            26,
            itemid("artmet01p", "net.tcp.service[http,,8080]"),
            "Docker metrics exporter",
            "ART20",
        ),
        graph_widget(
            "CPU utilization by tier",
            0,
            29,
            [
                {"host": "arthpx01p", "item": "CPU utilization", "color": "7E57C2"},
                {"host": "artweb01p", "item": "CPU utilization", "color": "42A5F5"},
                {"host": "artweb02p", "item": "CPU utilization", "color": "29B6F6"},
                {"host": "artbdd01p", "item": "CPU utilization", "color": "66BB6A"},
                {"host": "artbdd02p", "item": "CPU utilization", "color": "9CCC65"},
                {"host": "artprom01p", "item": "CPU utilization", "color": "FFA726"},
                {"host": "artgrf01p", "item": "CPU utilization", "color": "EF5350"},
            ],
            "ART21",
        ),
        graph_widget(
            "Memory utilization by tier",
            36,
            29,
            [
                {"host": "arthpx01p", "item": "Memory utilization", "color": "7E57C2"},
                {"host": "artweb01p", "item": "Memory utilization", "color": "42A5F5"},
                {"host": "artweb02p", "item": "Memory utilization", "color": "29B6F6"},
                {"host": "artbdd01p", "item": "Memory utilization", "color": "66BB6A"},
                {"host": "artbdd02p", "item": "Memory utilization", "color": "9CCC65"},
                {"host": "artprom01p", "item": "Memory utilization", "color": "FFA726"},
                {"host": "artgrf01p", "item": "Memory utilization", "color": "EF5350"},
            ],
            "ART22",
        ),
        graph_widget(
            "Nginx direct activity",
            0,
            35,
            [
                {"host": "artweb01p", "item": "Requests per second", "color": "42A5F5"},
                {"host": "artweb02p", "item": "Requests per second", "color": "FFA726"},
                {"host": "artweb01p", "item": "Connections active", "color": "66BB6A"},
                {"host": "artweb02p", "item": "Connections active", "color": "EF5350"},
            ],
            "ART23",
        ),
        graph_widget(
            "HAProxy backend distribution",
            36,
            35,
            [
                {"host": "arthpx01p", "item": "nginx_backends artweb01p: Server was selected per second", "color": "42A5F5"},
                {"host": "arthpx01p", "item": "nginx_backends artweb02p: Server was selected per second", "color": "FFA726"},
                {"host": "arthpx01p", "item": "nginx_backends artweb01p: Responses time", "color": "66BB6A"},
                {"host": "arthpx01p", "item": "nginx_backends artweb02p: Responses time", "color": "EF5350"},
            ],
            "ART24",
        ),
        graph_widget(
            "PostgreSQL TCP response time",
            0,
            41,
            [
                {"host": "artbdd01p", "item": "PostgreSQL primary TCP response time", "color": "66BB6A"},
                {"host": "artbdd02p", "item": "PostgreSQL replica TCP response time", "color": "42A5F5"},
            ],
            "ART25",
        ),
        graph_widget(
            "Monitoring endpoints response time",
            36,
            41,
            [
                {"host": "artzabweb01p", "item": "Zabbix web HTTP response time", "color": "66BB6A"},
                {"host": "artprom01p", "item": "Prometheus HTTP response time", "color": "FFA726"},
                {"host": "artgrf01p", "item": "Grafana HTTP response time", "color": "42A5F5"},
                {"host": "artnag01p", "item": "Nagios HTTP response time", "color": "EF5350"},
                {"host": "artmet01p", "item": "Docker metrics HTTP response time", "color": "AB47BC"},
            ],
            "ART26",
        ),
        graph_widget(
            "Network receive by service",
            0,
            47,
            [
                {"host": "arthpx01p", "item": "Interface eth0: Bits received", "color": "7E57C2"},
                {"host": "artweb01p", "item": "Interface eth0: Bits received", "color": "42A5F5"},
                {"host": "artweb02p", "item": "Interface eth0: Bits received", "color": "29B6F6"},
                {"host": "artbdd01p", "item": "Interface eth0: Bits received", "color": "66BB6A"},
                {"host": "artbdd02p", "item": "Interface eth0: Bits received", "color": "9CCC65"},
                {"host": "artmet01p", "item": "Interface eth0: Bits received", "color": "FFA726"},
                {"host": "artgrf01p", "item": "Interface eth0: Bits received", "color": "EF5350"},
            ],
            "ART27",
        ),
        graph_widget(
            "Network send by service",
            36,
            47,
            [
                {"host": "arthpx01p", "item": "Interface eth0: Bits sent", "color": "7E57C2"},
                {"host": "artweb01p", "item": "Interface eth0: Bits sent", "color": "42A5F5"},
                {"host": "artweb02p", "item": "Interface eth0: Bits sent", "color": "29B6F6"},
                {"host": "artbdd01p", "item": "Interface eth0: Bits sent", "color": "66BB6A"},
                {"host": "artbdd02p", "item": "Interface eth0: Bits sent", "color": "9CCC65"},
                {"host": "artmet01p", "item": "Interface eth0: Bits sent", "color": "FFA726"},
                {"host": "artgrf01p", "item": "Interface eth0: Bits sent", "color": "EF5350"},
            ],
            "ART28",
        ),
    ]

    payload = {
        "name": "Artemis Supervision",
        "private": 0,
        "display_period": 30,
        "auto_start": 1,
        "pages": [{"name": "Overview", "display_period": 0, "widgets": widgets}],
    }

    existing = call(
        "dashboard.get",
        {"filter": {"name": ["Artemis Supervision"]}, "output": ["dashboardid"]},
        token,
    )
    if existing:
        payload["dashboardid"] = existing[0]["dashboardid"]
        call("dashboard.update", payload, token)
        print("Updated Zabbix dashboard: Artemis Supervision")
    else:
        call("dashboard.create", payload, token)
        print("Created Zabbix dashboard: Artemis Supervision")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(exc, file=sys.stderr)
        sys.exit(1)
