# Eagle Construction Company Website Deployment

This branch is isolated from the dg-business-suite main branch.

The site is packaged as eagle-site.zip. On Render use `unzip -q eagle-site.zip` for the build step and `node eagle-construction-website/server.mjs` for the start command. Set NODE_ENV=production, ADMIN_PASSWORD, SESSION_SECRET, and attach persistent DATA_DIR storage before accepting genuine customer enquiries.
