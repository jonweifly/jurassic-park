const canvas = document.querySelector("#game");
const ctx = canvas.getContext("2d");

const ui = {
  wood: document.querySelector("#wood"),
  meat: document.querySelector("#meat"),
  power: document.querySelector("#power"),
  wave: document.querySelector("#wave"),
  timer: document.querySelector("#timer"),
  hpText: document.querySelector("#hpText"),
  hpBar: document.querySelector("#hpBar"),
  xpText: document.querySelector("#xpText"),
  xpBar: document.querySelector("#xpBar"),
  heroStatus: document.querySelector("#heroStatus"),
  questText: document.querySelector("#questText"),
  toast: document.querySelector("#toast"),
  logList: document.querySelector("#logList"),
  buildButtons: [...document.querySelectorAll(".build")]
};

const world = {
  width: 2600,
  height: 1600,
  time: 0,
  wave: 0,
  nextWave: 22,
  waveActive: false,
  gameOver: false,
  victory: false,
  shake: 0
};

const keys = new Set();
const mouse = { x: 0, y: 0, worldX: 0, worldY: 0, down: false };
const camera = { x: 0, y: 0 };
let buildMode = "turret";
let toastTimer = 0;
let attackCooldown = 0;

const assets = {};
const assetSources = {
  ranger: "/assets/ranger.svg",
  raptor: "/assets/raptor.svg",
  trex: "/assets/trex.svg",
  turret: "/assets/turret.svg",
  fence: "/assets/fence.svg",
  trap: "/assets/trap.svg",
  generator: "/assets/generator.svg",
  visitor: "/assets/visitor-center.svg",
  tree: "/assets/tree.svg",
  crate: "/assets/crate.svg"
};

const resources = {
  wood: 120,
  meat: 45,
  power: 80
};

const hero = {
  x: 1240,
  y: 980,
  r: 18,
  hp: 120,
  maxHp: 120,
  speed: 210,
  damage: 24,
  level: 1,
  xp: 0,
  xpNext: 80,
  dir: 0,
  alive: true
};

const base = {
  x: 1300,
  y: 820,
  r: 74,
  hp: 620,
  maxHp: 620
};

const generator = {
  x: 1130,
  y: 775,
  r: 42,
  hp: 150,
  maxHp: 150,
  repair: 34,
  online: false
};

const entities = {
  dinos: [],
  bullets: [],
  buildings: [
    { type: "turret", x: 1435, y: 910, r: 24, hp: 160, maxHp: 160, cd: 0 },
    { type: "fence", x: 1220, y: 710, r: 26, hp: 190, maxHp: 190 },
    { type: "fence", x: 1380, y: 710, r: 26, hp: 190, maxHp: 190 }
  ],
  pickups: [],
  trees: [],
  crates: [],
  particles: []
};

const buildCosts = {
  turret: { wood: 80, power: 25 },
  fence: { wood: 35, power: 10 },
  trap: { wood: 45, meat: 15 }
};

const terrain = {
  water: [
    { x: 180, y: 1180, rx: 360, ry: 150 },
    { x: 2380, y: 310, rx: 290, ry: 130 }
  ],
  paths: [
    { x1: 80, y1: 840, x2: 2480, y2: 900, width: 96 },
    { x1: 1300, y1: 180, x2: 1260, y2: 1480, width: 78 }
  ]
};

function rand(min, max) {
  return min + Math.random() * (max - min);
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function loadImage(src) {
  return new Promise((resolve) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => resolve(null);
    image.src = src;
  });
}

async function loadAssets() {
  await Promise.all(
    Object.entries(assetSources).map(async ([key, src]) => {
      assets[key] = await loadImage(src);
    })
  );
}

function seedMap() {
  for (let i = 0; i < 92; i++) {
    const nearBase = i < 22;
    const angle = rand(0, Math.PI * 2);
    const radius = nearBase ? rand(280, 680) : rand(100, 1220);
    entities.trees.push({
      x: clamp(base.x + Math.cos(angle) * radius + rand(-120, 120), 80, world.width - 80),
      y: clamp(base.y + Math.sin(angle) * radius + rand(-120, 120), 80, world.height - 80),
      r: rand(19, 31),
      hp: 45,
      maxHp: 45
    });
  }

  for (let i = 0; i < 18; i++) {
    entities.crates.push({
      x: rand(160, world.width - 160),
      y: rand(160, world.height - 160),
      r: 19,
      used: false
    });
  }

  log("直升机撤离失败，游客中心必须坚守到第 8 波。");
  showToast("先采集资源并修复发电机，第一波即将到来。");
}

function showToast(message) {
  ui.toast.textContent = message;
  ui.toast.classList.add("show");
  toastTimer = 2.8;
}

function log(message) {
  const li = document.createElement("li");
  li.textContent = message;
  ui.logList.append(li);
  while (ui.logList.children.length > 8) ui.logList.firstChild.remove();
}

function spawnWave(wave) {
  world.waveActive = true;
  const count = 5 + wave * 3;
  for (let i = 0; i < count; i++) {
    const side = Math.floor(rand(0, 4));
    const p = [
      { x: rand(0, world.width), y: -60 },
      { x: world.width + 60, y: rand(0, world.height) },
      { x: rand(0, world.width), y: world.height + 60 },
      { x: -60, y: rand(0, world.height) }
    ][side];
    const heavy = wave >= 3 && Math.random() < 0.18 + wave * 0.018;
    entities.dinos.push({
      kind: heavy ? "trex" : "raptor",
      x: p.x + rand(-80, 80),
      y: p.y + rand(-80, 80),
      r: heavy ? 34 : 20,
      hp: heavy ? 155 + wave * 18 : 58 + wave * 8,
      maxHp: heavy ? 155 + wave * 18 : 58 + wave * 8,
      speed: heavy ? 72 + wave * 2 : 108 + wave * 3,
      damage: heavy ? 28 + wave * 2 : 12 + wave,
      attackCd: rand(0, 1.2),
      slow: 0,
      dir: 0
    });
  }
  log(`第 ${wave} 波恐龙正在突破围栏。`);
  showToast(`第 ${wave} 波来袭`);
}

function canPay(cost) {
  return Object.entries(cost).every(([key, value]) => resources[key] >= value);
}

function pay(cost) {
  for (const [key, value] of Object.entries(cost)) resources[key] -= value;
}

function buildAt(x, y) {
  if (world.gameOver || world.victory) return;
  if (dist({ x, y }, base) < 96 || dist({ x, y }, generator) < 70) {
    showToast("建筑离关键设施太近。");
    return;
  }
  if (entities.buildings.some((b) => Math.hypot(b.x - x, b.y - y) < 58)) {
    showToast("这里已经有建筑。");
    return;
  }
  const cost = buildCosts[buildMode];
  if (!canPay(cost)) {
    showToast("资源不足。");
    return;
  }
  pay(cost);
  const hp = buildMode === "turret" ? 160 : buildMode === "fence" ? 190 : 80;
  entities.buildings.push({ type: buildMode, x, y, r: buildMode === "trap" ? 23 : 26, hp, maxHp: hp, cd: 0, armed: true });
  log(`${buildMode === "turret" ? "自动炮塔" : buildMode === "fence" ? "高压围栏" : "麻醉陷阱"} 已部署。`);
}

function handleInput(dt) {
  let dx = 0;
  let dy = 0;
  if (keys.has("w") || keys.has("arrowup")) dy -= 1;
  if (keys.has("s") || keys.has("arrowdown")) dy += 1;
  if (keys.has("a") || keys.has("arrowleft")) dx -= 1;
  if (keys.has("d") || keys.has("arrowright")) dx += 1;
  if (dx || dy) {
    const mag = Math.hypot(dx, dy);
    dx /= mag;
    dy /= mag;
    hero.x = clamp(hero.x + dx * hero.speed * dt, hero.r, world.width - hero.r);
    hero.y = clamp(hero.y + dy * hero.speed * dt, hero.r, world.height - hero.r);
    hero.dir = Math.atan2(dy, dx);
  }

  if (keys.has("q")) {
    keys.delete("q");
    if (resources.meat >= 18 && hero.hp < hero.maxHp) {
      resources.meat -= 18;
      hero.hp = Math.min(hero.maxHp, hero.hp + 46);
      addParticles(hero.x, hero.y, "#75e890", 16);
      showToast("使用补给包。");
    }
  }

  attackCooldown = Math.max(0, attackCooldown - dt);
  if (mouse.down && attackCooldown <= 0) {
    interact();
    attackCooldown = 0.24;
  }
}

function interact() {
  const target = { x: mouse.worldX, y: mouse.worldY };
  const heroReach = Math.hypot(hero.x - target.x, hero.y - target.y) < 170;
  if (!heroReach) return;

  const tree = entities.trees.find((t) => Math.hypot(t.x - target.x, t.y - target.y) < t.r + 18);
  if (tree) {
    tree.hp -= hero.damage;
    addParticles(tree.x, tree.y, "#7fb45c", 8);
    if (tree.hp <= 0) {
      resources.wood += 22 + Math.floor(rand(0, 14));
      entities.trees = entities.trees.filter((t) => t !== tree);
      log("采集到木材。");
    }
    return;
  }

  const crate = entities.crates.find((c) => !c.used && Math.hypot(c.x - target.x, c.y - target.y) < c.r + 18);
  if (crate) {
    crate.used = true;
    resources.wood += 20;
    resources.meat += 18;
    resources.power += 12;
    addParticles(crate.x, crate.y, "#e4b55f", 18);
    log("回收到补给箱。");
    return;
  }

  if (dist(hero, generator) < 120 && dist(target, generator) < 92 && !generator.online) {
    generator.repair += 10;
    resources.power += 2;
    addParticles(generator.x, generator.y, "#71d5ff", 10);
    if (generator.repair >= 100) {
      generator.online = true;
      resources.power += 80;
      log("主发电机上线，炮塔火控恢复。");
      showToast("主线任务完成：发电机已上线。");
    }
    return;
  }

  const dino = entities.dinos
    .filter((d) => Math.hypot(d.x - target.x, d.y - target.y) < d.r + 22)
    .sort((a, b) => dist(a, hero) - dist(b, hero))[0];
  if (dino && dist(dino, hero) < 190) {
    dino.hp -= hero.damage;
    dino.slow = Math.max(dino.slow, 0.2);
    addParticles(dino.x, dino.y, "#d45a43", 10);
    if (dino.hp <= 0) killDino(dino);
  }
}

function updateDinos(dt) {
  for (const dino of [...entities.dinos]) {
    dino.slow = Math.max(0, dino.slow - dt);
    dino.attackCd = Math.max(0, dino.attackCd - dt);

    let target = base;
    const livingBuildings = entities.buildings.filter((b) => b.hp > 0);
    const closestBuilding = livingBuildings.sort((a, b) => dist(a, dino) - dist(b, dino))[0];
    if (closestBuilding && dist(closestBuilding, dino) < 310) target = closestBuilding;
    if (dist(hero, dino) < 260) target = hero;

    const dx = target.x - dino.x;
    const dy = target.y - dino.y;
    const distance = Math.hypot(dx, dy) || 1;
    dino.dir = Math.atan2(dy, dx);

    if (distance > dino.r + (target.r || 18) + 8) {
      const speed = dino.speed * (dino.slow > 0 ? 0.45 : 1);
      dino.x += (dx / distance) * speed * dt;
      dino.y += (dy / distance) * speed * dt;
    } else if (dino.attackCd <= 0) {
      target.hp -= dino.damage;
      dino.attackCd = dino.kind === "trex" ? 1.25 : 0.86;
      world.shake = Math.max(world.shake, dino.kind === "trex" ? 7 : 3);
      addParticles(target.x, target.y, "#d45a43", 8);
      if (target === hero && hero.hp <= 0) endGame(false, "巡林员阵亡。");
      if (target === base && base.hp <= 0) endGame(false, "游客中心被摧毁。");
    }
  }

  entities.buildings = entities.buildings.filter((b) => b.hp > 0);
}

function updateBuildings(dt) {
  for (const building of entities.buildings) {
    if (building.type === "turret") {
      building.cd = Math.max(0, (building.cd || 0) - dt);
      const target = entities.dinos.filter((d) => dist(d, building) < 340).sort((a, b) => dist(a, building) - dist(b, building))[0];
      if (target && building.cd <= 0) {
        building.cd = generator.online ? 0.48 : 1.1;
        entities.bullets.push({
          x: building.x,
          y: building.y,
          tx: target.x,
          ty: target.y,
          target,
          speed: 580,
          damage: generator.online ? 34 : 18,
          life: 1.1
        });
      }
    }

    if (building.type === "trap" && building.armed) {
      const target = entities.dinos.find((d) => dist(d, building) < building.r + d.r);
      if (target) {
        target.hp -= 65;
        target.slow = 3.4;
        building.armed = false;
        building.hp = 0;
        addParticles(building.x, building.y, "#69d7ff", 32);
        log("麻醉陷阱触发。");
        if (target.hp <= 0) killDino(target);
      }
    }
  }
}

function updateBullets(dt) {
  for (const bullet of [...entities.bullets]) {
    bullet.life -= dt;
    if (!bullet.target || bullet.target.hp <= 0 || bullet.life <= 0) {
      entities.bullets = entities.bullets.filter((b) => b !== bullet);
      continue;
    }
    const dx = bullet.target.x - bullet.x;
    const dy = bullet.target.y - bullet.y;
    const distance = Math.hypot(dx, dy) || 1;
    bullet.x += (dx / distance) * bullet.speed * dt;
    bullet.y += (dy / distance) * bullet.speed * dt;
    if (distance < bullet.target.r + 8) {
      bullet.target.hp -= bullet.damage;
      addParticles(bullet.target.x, bullet.target.y, "#f2d76c", 8);
      if (bullet.target.hp <= 0) killDino(bullet.target);
      entities.bullets = entities.bullets.filter((b) => b !== bullet);
    }
  }
}

function killDino(dino) {
  resources.meat += dino.kind === "trex" ? 18 : 7;
  hero.xp += dino.kind === "trex" ? 46 : 18;
  entities.dinos = entities.dinos.filter((d) => d !== dino);
  addParticles(dino.x, dino.y, "#b84b36", dino.kind === "trex" ? 26 : 14);
  if (hero.xp >= hero.xpNext) {
    hero.xp -= hero.xpNext;
    hero.level += 1;
    hero.xpNext = Math.floor(hero.xpNext * 1.42);
    hero.maxHp += 18;
    hero.hp = hero.maxHp;
    hero.damage += 6;
    log(`巡林员升到 ${hero.level} 级。`);
    showToast("等级提升");
  }
}

function updateWorld(dt) {
  if (world.gameOver || world.victory) return;
  world.time += dt;
  world.nextWave -= dt;
  world.shake = Math.max(0, world.shake - 28 * dt);

  if (generator.online) resources.power += dt * 1.2;
  resources.wood += dt * 0.38;

  if (world.nextWave <= 0) {
    world.wave += 1;
    if (world.wave > 8) {
      endGame(true, "救援队抵达，游客中心保住了。");
      return;
    }
    world.nextWave = Math.max(18, 34 - world.wave * 1.7);
    spawnWave(world.wave);
  }

  if (world.waveActive && entities.dinos.length === 0) {
    world.waveActive = false;
    if (world.nextWave > 9) world.nextWave = 9;
  }

  updateBuildings(dt);
  updateBullets(dt);
  updateDinos(dt);
  updateParticles(dt);
}

function endGame(victory, message) {
  world.gameOver = !victory;
  world.victory = victory;
  showToast(victory ? "任务完成" : "任务失败");
  log(message);
}

function addParticles(x, y, color, count) {
  for (let i = 0; i < count; i++) {
    entities.particles.push({
      x,
      y,
      vx: rand(-90, 90),
      vy: rand(-90, 90),
      life: rand(0.28, 0.72),
      maxLife: 0.72,
      color
    });
  }
}

function updateParticles(dt) {
  for (const p of entities.particles) {
    p.life -= dt;
    p.x += p.vx * dt;
    p.y += p.vy * dt;
  }
  entities.particles = entities.particles.filter((p) => p.life > 0);
}

function updateCamera() {
  camera.x = clamp(hero.x - canvas.width / 2, 0, world.width - canvas.width);
  camera.y = clamp(hero.y - canvas.height / 2, 0, world.height - canvas.height);
  if (world.shake > 0) {
    camera.x += rand(-world.shake, world.shake);
    camera.y += rand(-world.shake, world.shake);
  }
}

function worldToScreen(entity) {
  return { x: entity.x - camera.x, y: entity.y - camera.y };
}

function drawImageCentered(key, x, y, size, angle = 0) {
  const image = assets[key];
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(angle);
  if (image) {
    ctx.drawImage(image, -size / 2, -size / 2, size, size);
  } else {
    ctx.fillStyle = "#d7c071";
    ctx.beginPath();
    ctx.arc(0, 0, size / 2, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function drawTerrain() {
  ctx.fillStyle = "#223726";
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  ctx.save();
  ctx.translate(-camera.x, -camera.y);
  ctx.strokeStyle = "rgba(124, 104, 69, 0.72)";
  ctx.lineCap = "round";
  for (const path of terrain.paths) {
    ctx.lineWidth = path.width;
    ctx.beginPath();
    ctx.moveTo(path.x1, path.y1);
    ctx.lineTo(path.x2, path.y2);
    ctx.stroke();
    ctx.strokeStyle = "rgba(191, 167, 104, 0.22)";
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.strokeStyle = "rgba(124, 104, 69, 0.72)";
  }

  for (let x = 0; x < world.width; x += 90) {
    for (let y = 0; y < world.height; y += 90) {
      const hash = Math.sin(x * 13.17 + y * 5.31) * 10000;
      const n = hash - Math.floor(hash);
      if (n > 0.76) {
        ctx.fillStyle = n > 0.9 ? "rgba(84, 122, 57, 0.35)" : "rgba(38, 79, 48, 0.4)";
        ctx.beginPath();
        ctx.arc(x + 12, y + 20, 10 + n * 10, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  for (const lake of terrain.water) {
    ctx.fillStyle = "#244b58";
    ctx.beginPath();
    ctx.ellipse(lake.x, lake.y, lake.rx, lake.ry, -0.2, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "rgba(137, 210, 215, 0.3)";
    ctx.lineWidth = 8;
    ctx.stroke();
  }
  ctx.restore();
}

function drawHealthBar(entity, width = 54) {
  const s = worldToScreen(entity);
  const y = s.y - entity.r - 14;
  ctx.fillStyle = "rgba(0, 0, 0, 0.58)";
  ctx.fillRect(s.x - width / 2, y, width, 6);
  ctx.fillStyle = entity.hp / entity.maxHp > 0.4 ? "#6fdd72" : "#e25d4f";
  ctx.fillRect(s.x - width / 2, y, width * clamp(entity.hp / entity.maxHp, 0, 1), 6);
}

function drawWorld() {
  drawTerrain();

  ctx.save();
  ctx.translate(-camera.x, -camera.y);

  ctx.fillStyle = "rgba(5, 9, 7, 0.32)";
  ctx.beginPath();
  ctx.ellipse(base.x, base.y + 42, 124, 54, 0, 0, Math.PI * 2);
  ctx.fill();
  drawImageCentered("visitor", base.x, base.y, 150, 0);
  ctx.fillStyle = "rgba(255, 238, 156, 0.12)";
  ctx.beginPath();
  ctx.arc(base.x, base.y, 132, 0, Math.PI * 2);
  ctx.fill();

  drawImageCentered("generator", generator.x, generator.y, 84, 0);
  if (!generator.online) {
    ctx.fillStyle = "rgba(113, 213, 255, 0.8)";
    ctx.fillRect(generator.x - 42, generator.y + 52, 84 * clamp(generator.repair / 100, 0, 1), 6);
    ctx.strokeStyle = "rgba(0, 0, 0, 0.55)";
    ctx.strokeRect(generator.x - 42, generator.y + 52, 84, 6);
  } else {
    ctx.strokeStyle = "rgba(108, 229, 127, 0.82)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(generator.x, generator.y, 54 + Math.sin(world.time * 5) * 3, 0, Math.PI * 2);
    ctx.stroke();
  }

  for (const crate of entities.crates) {
    if (!crate.used) drawImageCentered("crate", crate.x, crate.y, 42, 0);
  }

  for (const tree of entities.trees) {
    drawImageCentered("tree", tree.x, tree.y, tree.r * 2.7, 0);
  }

  for (const building of entities.buildings) {
    const key = building.type === "turret" ? "turret" : building.type === "fence" ? "fence" : "trap";
    drawImageCentered(key, building.x, building.y, building.type === "turret" ? 58 : 54, 0);
    if (building.hp < building.maxHp) drawHealthBar(building, 46);
  }

  for (const bullet of entities.bullets) {
    ctx.strokeStyle = "#ffe175";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(bullet.x, bullet.y);
    ctx.lineTo(bullet.x - Math.cos(Math.atan2(bullet.ty - bullet.y, bullet.tx - bullet.x)) * 12, bullet.y);
    ctx.stroke();
    ctx.fillStyle = "#fff0a0";
    ctx.beginPath();
    ctx.arc(bullet.x, bullet.y, 4, 0, Math.PI * 2);
    ctx.fill();
  }

  for (const dino of entities.dinos) {
    drawImageCentered(dino.kind, dino.x, dino.y, dino.kind === "trex" ? 88 : 54, dino.dir);
    drawHealthBar(dino, dino.kind === "trex" ? 68 : 46);
  }

  drawImageCentered("ranger", hero.x, hero.y, 54, hero.dir);
  drawHealthBar(hero, 54);

  for (const p of entities.particles) {
    ctx.globalAlpha = clamp(p.life / p.maxLife, 0, 1);
    ctx.fillStyle = p.color;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 3.4, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;

  if (buildMode) {
    const cost = buildCosts[buildMode];
    const valid = canPay(cost);
    ctx.strokeStyle = valid ? "rgba(228, 181, 95, 0.85)" : "rgba(229, 106, 84, 0.85)";
    ctx.fillStyle = valid ? "rgba(228, 181, 95, 0.12)" : "rgba(229, 106, 84, 0.12)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(mouse.worldX, mouse.worldY, buildMode === "turret" ? 28 : 24, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    if (buildMode === "turret") {
      ctx.strokeStyle = "rgba(228, 181, 95, 0.18)";
      ctx.beginPath();
      ctx.arc(mouse.worldX, mouse.worldY, 340, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  ctx.restore();

  drawOverlay();
}

function drawOverlay() {
  const baseScreen = worldToScreen(base);
  ctx.fillStyle = "rgba(0, 0, 0, 0.58)";
  ctx.fillRect(baseScreen.x - 80, baseScreen.y - 105, 160, 9);
  ctx.fillStyle = "#6fdd72";
  ctx.fillRect(baseScreen.x - 80, baseScreen.y - 105, 160 * clamp(base.hp / base.maxHp, 0, 1), 9);

  if (world.gameOver || world.victory) {
    ctx.fillStyle = "rgba(6, 8, 7, 0.72)";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = world.victory ? "#e4d16d" : "#e56a54";
    ctx.font = "700 54px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(world.victory ? "公园幸存" : "公园失守", canvas.width / 2, canvas.height / 2 - 20);
    ctx.fillStyle = "#edf6df";
    ctx.font = "20px system-ui, sans-serif";
    ctx.fillText("刷新页面重新开始", canvas.width / 2, canvas.height / 2 + 30);
    ctx.textAlign = "start";
  }
}

function updateUi() {
  ui.wood.textContent = Math.floor(resources.wood);
  ui.meat.textContent = Math.floor(resources.meat);
  ui.power.textContent = Math.floor(resources.power);
  ui.wave.textContent = world.wave === 0 ? "准备" : `${world.wave}/8`;
  const elapsed = Math.floor(world.time);
  ui.timer.textContent = `${String(Math.floor(elapsed / 60)).padStart(2, "0")}:${String(elapsed % 60).padStart(2, "0")}`;
  ui.hpText.textContent = `${Math.max(0, Math.floor(hero.hp))} / ${hero.maxHp}`;
  ui.hpBar.style.width = `${clamp(hero.hp / hero.maxHp, 0, 1) * 100}%`;
  ui.xpText.textContent = `${Math.floor(hero.xp)} / ${hero.xpNext}`;
  ui.xpBar.style.width = `${clamp(hero.xp / hero.xpNext, 0, 1) * 100}%`;
  ui.heroStatus.textContent = `等级 ${hero.level} / ${hero.hp > hero.maxHp * 0.4 ? "可战斗" : "重伤"}`;
  ui.questText.textContent = generator.online
    ? `坚守游客中心到第 8 波。下一波 ${Math.ceil(world.nextWave)} 秒后。`
    : `修复发电机：${Math.floor(generator.repair)}%。靠近后点击发电机。`;

  if (toastTimer > 0) {
    toastTimer -= 1 / 60;
  } else {
    ui.toast.classList.remove("show");
  }
}

function resizeCanvas() {
  const frame = canvas.parentElement.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;
  canvas.width = Math.max(960, Math.floor(frame.width * scale));
  canvas.height = Math.max(540, Math.floor(frame.height * scale));
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  canvas.width = Math.floor(frame.width);
  canvas.height = Math.floor(frame.height);
}

function setBuildMode(mode) {
  buildMode = mode;
  ui.buildButtons.forEach((button) => button.classList.toggle("active", button.dataset.build === mode));
}

ui.buildButtons.forEach((button) => {
  button.addEventListener("click", () => setBuildMode(button.dataset.build));
});

window.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  keys.add(key);
  if (key === "1") setBuildMode("turret");
  if (key === "2") setBuildMode("fence");
  if (key === "3") setBuildMode("trap");
});

window.addEventListener("keyup", (event) => keys.delete(event.key.toLowerCase()));
window.addEventListener("resize", resizeCanvas);

canvas.addEventListener("mousemove", (event) => {
  const rect = canvas.getBoundingClientRect();
  mouse.x = event.clientX - rect.left;
  mouse.y = event.clientY - rect.top;
  mouse.worldX = mouse.x + camera.x;
  mouse.worldY = mouse.y + camera.y;
});

canvas.addEventListener("mousedown", (event) => {
  if (event.button !== 0) return;
  mouse.down = true;
  if (keys.has("shift")) {
    interact();
  } else if (Math.hypot(mouse.worldX - hero.x, mouse.worldY - hero.y) > 190) {
    buildAt(mouse.worldX, mouse.worldY);
  } else {
    interact();
  }
});

window.addEventListener("mouseup", () => {
  mouse.down = false;
});

let last = performance.now();
function loop(now) {
  const dt = Math.min(0.033, (now - last) / 1000);
  last = now;
  handleInput(dt);
  updateWorld(dt);
  updateCamera();
  drawWorld();
  updateUi();
  requestAnimationFrame(loop);
}

resizeCanvas();
await loadAssets();
seedMap();
requestAnimationFrame(loop);
