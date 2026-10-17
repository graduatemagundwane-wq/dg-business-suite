# Yola registration → Master approval → sign-in (candidate)

## Customer flow
1. Create Yola business account with owner-chosen email and 12+ character password.
2. The server commits customer, `inactive` installation, Yola owner and Master Control `product_accounts` in one transaction. The response returns only after commit.
3. The UI immediately switches to a dedicated `?activation=waiting` view displaying business name and registration code.
4. The waiting view polls `/api/me` every 7 seconds. Reloading retains the waiting view because the URL records its state; the license is always read from Master Control, not a local toggle.
5. When Master Control changes the installation to `active`, Yola calls `/api/logout`, displays a visible approval confirmation and shows the **Sign in** form.
6. Only fresh valid sign-in credentials redirect to the POS workspace.

## Master Control appearance
- Record insertion is atomic and immediately queryable in Neon; new Yola clients do not require adding manually in Master Control.
- The current Master Control web dashboard refreshes open product/customer lists every **30 seconds** when the tab is visible and there is no active form or modal. Thus database visibility is immediate, UI visibility is within the next normal poll. A manual refresh also displays the new record.

## Test evidence
- `npm test`: 24/24 Node tests passed, including simulated automatic polling to signed-in state and atomic registration source checks.
- `node --check public/app.js`: passed.
- Chromium automation was attempted but the environment blocked localhost and test domain with `ERR_BLOCKED_BY_ADMINISTRATOR`. Do not claim browser rendering passed.

## Deployment
- This source update has not been confirmed live at `https://yola-onboarding.vercel.app` until a new production deployment is published and `/app.js` is verified. The current Vercel team had a daily deployment API quota error (402); if that persists, the tested source remains a release candidate.
- Updating the web frontend updates the Windows EXE flow because the EXE embeds the hosted Yola website; no licence authority is changed.