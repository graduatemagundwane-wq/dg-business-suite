"""Catch mobile UI menu links pointing to forbidden or missing API resources."""
from pathlib import Path
import re
from test_api import appctx

APP_SOURCE=Path(__file__).resolve().parents[2] / 'mobile' / 'App.tsx'

def parse_array_role_map(source: str):
    body=source.split('const MENU:Record<string,string[]> = {',1)[1].split('\n};',1)[0]
    return {key:set(re.findall(r"'([^']+)'",items))
            for key,items in re.findall(r'^  (\w+):\[([^\]]*)\],?',body,re.M)}

def parse_path_map(source: str):
    body=source.split('const PATHS:Record<string,string>={',1)[1].split('};',1)[0]
    return {k:v for k,v in re.findall(r"(\w+):'([^']+)'",body)}

def test_authorized_mobile_menu_routes_are_reachable(appctx):
    client, ids, headers=appctx
    source=APP_SOURCE.read_text()
    menu=parse_array_role_map(source)
    paths=parse_path_map(source)
    assert len(menu)>=25
    mismatches=[]
    for screen,roles in menu.items():
        if screen in {'dashboard','account'}:continue
        path='/api'+paths.get(screen,'/'+screen)
        for role in roles|{'owner'}:
            if role not in headers:continue
            response=client.get(path,headers=headers[role])
            if response.status_code not in (200,):
                mismatches.append((screen,role,path,response.status_code))
    assert mismatches==[],mismatches
