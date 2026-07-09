'use strict';
// Shrimp eşleştirme kodu: {host, port, token} → base64. Kullanıcı bunu Mac'teki
// Shrimp kurulum sihirbazına yapıştırır → tek adımda bağlanır.
const config = require('../src/config');
const cfg = config.load();
const host = process.env.CLAUDE_REMOTE_HOST || config.resolveHost(cfg);
const payload = { v: 1, host, port: cfg.port, token: cfg.token };
const code = Buffer.from(JSON.stringify(payload)).toString('base64');

console.log('');
console.log('  ┌─────────────────────────────────────────────────────────┐');
console.log('  │  Shrimp EŞLEŞTİRME KODU — Mac uygulamasına yapıştır:      │');
console.log('  └─────────────────────────────────────────────────────────┘');
console.log('');
console.log('  ' + code);
console.log('');
console.log('  (host: ' + host + '  port: ' + cfg.port + ')');
console.log('');
