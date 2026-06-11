const fs = require('fs');
const file = 'packages/web/server/lib/opencode/core-routes.js';
if (fs.existsSync(file)) {
  const content = fs.readFileSync(file, 'utf8');
  const target = "req.path.startsWith('/api/session-folders') ||";
  const replacement = "req.path.startsWith('/api/session-folders') ||\n      req.path.startsWith('/api/session') ||";
  if (!content.includes(target)) {
    throw new Error('Target string not found in core-routes.js');
  }
  fs.writeFileSync(file, content.replace(target, replacement));
  console.log('Successfully patched core-routes.js');
} else {
  throw new Error('core-routes.js file not found');
}
