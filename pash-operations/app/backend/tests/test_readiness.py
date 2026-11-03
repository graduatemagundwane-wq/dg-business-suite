"""Only infrastructure readiness is checked. Never label it production acceptance."""
import os
from test_api import appctx

def test_ready_when_full_schema_and_secret_are_present(appctx):
    client, _, _=appctx
    response=client.get('/api/ready')
    assert response.status_code==200,response.text
    assert response.json()=={'ready':True,'schema_complete':True,'advanced_schema':True,'configuration_ok':True}

def test_production_cannot_claim_ready_with_sqlite(appctx,monkeypatch):
    monkeypatch.setenv('PASH_ENV','production')
    client,_,_=appctx
    r=client.get('/api/ready')
    assert r.status_code==503
    assert r.json()['ready'] is False

def test_missing_secret_cannot_claim_ready(appctx,monkeypatch):
    monkeypatch.delenv('PASH_JWT_SECRET',raising=False)
    client,_,_=appctx
    r=client.get('/api/ready')
    assert r.status_code==503
    assert r.json()['configuration_ok'] is False
