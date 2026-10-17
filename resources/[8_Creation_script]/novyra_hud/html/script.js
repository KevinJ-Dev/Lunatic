// novyra_hud | NightCraft Studio

const hud = document.getElementById('hud');
const inGame = typeof GetParentResourceName === 'function';

const RADIUS = 20;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;
const SEGMENTS = 12;

const ICONS = {
    health: '<path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>',
    armor: '<path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z"/>',
    hunger: '<path d="M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21V2c-2.76 0-5 2.24-5 4z"/>',
    thirst: '<path d="M12 2c-5.33 4.55-8 8.48-8 11.8 0 4.98 3.8 8.2 8 8.2s8-3.22 8-8.2c0-3.32-2.67-7.25-8-11.8z"/>',
    stamina: '<path d="M7 2v11h3v9l7-12h-4l4-8z"/>',
    oxygen: '<circle cx="8.5" cy="14.5" r="5"/><circle cx="17" cy="7" r="3.5"/><circle cx="18" cy="18" r="2.2"/>',
};

// Affiche a la place du coeur quand le joueur est mort
const SKULL = '<path fill-rule="evenodd" d="M12 2C7.2 2 3.5 5.6 3.5 10.2c0 2.8 1.3 5.1 3.5 6.6V19c0 .8.7 1.5 1.5 1.5h1v-2h1.5v2h2v-2h1.5v2h1c.8 0 1.5-.7 1.5-1.5v-2.2c2.2-1.5 3.5-3.8 3.5-6.6C20.5 5.6 16.8 2 12 2zM8.6 9a2 2 0 100 4 2 2 0 000-4zm6.8 0a2 2 0 100 4 2 2 0 000-4z"/>';

const WAVE = 'M-48 0Q-36 -2.6 -24 0T0 0T24 0T48 0T72 0T96 0V60H-48Z';

const items = {};
let lowThreshold = 20;
let animations = true;
let segmented = false;

// Eclaircit une couleur hexa en la melangeant avec du blanc
function lighten(hex, amount) {
    const clean = String(hex).replace('#', '');
    const full = clean.length === 3 ? clean.replace(/(.)/g, '$1$1') : clean;
    const num = parseInt(full, 16);
    if (Number.isNaN(num)) return '#ffffff';

    const mix = (channel) => Math.round(channel + (255 - channel) * amount);
    const r = mix((num >> 16) & 255);
    const g = mix((num >> 8) & 255);
    const b = mix(num & 255);
    return `rgb(${r}, ${g}, ${b})`;
}

function ringMarkup(name, color, color2, segmented) {
    const segment = CIRCUMFERENCE / SEGMENTS;
    const gap = 2.2;
    const mask = segmented
        ? `<mask id="mask-${name}" maskUnits="userSpaceOnUse" x="0" y="0" width="48" height="48">
               <circle cx="24" cy="24" r="${RADIUS}" fill="none" stroke="#fff" stroke-width="5"
                   stroke-dasharray="${segment - gap} ${gap}" stroke-dashoffset="${-gap / 2}"/>
           </mask>`
        : '';

    return `
        <svg class="gauge ring" viewBox="0 0 48 48">
            <defs>
                <linearGradient id="grad-${name}" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0" stop-color="${color2}"/>
                    <stop offset="1" stop-color="${color}"/>
                </linearGradient>
                ${mask}
            </defs>
            <g ${segmented ? `mask="url(#mask-${name})"` : ''}>
                <circle class="track" cx="24" cy="24" r="${RADIUS}"/>
                <circle class="value" cx="24" cy="24" r="${RADIUS}" stroke="url(#grad-${name})"
                    stroke-dasharray="${CIRCUMFERENCE}" stroke-dashoffset="${CIRCUMFERENCE}"/>
            </g>
        </svg>`;
}

function liquidMarkup(name, color, color2) {
    return `
        <svg class="gauge liquid" viewBox="0 0 48 48">
            <defs>
                <clipPath id="clip-${name}"><circle cx="24" cy="24" r="21"/></clipPath>
                <linearGradient id="grad-${name}" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0" stop-color="${color2}"/>
                    <stop offset="0.5" stop-color="${color}"/>
                </linearGradient>
            </defs>
            <g clip-path="url(#clip-${name})">
                <g class="level" style="transform: translateY(46px)">
                    <path class="wave back" d="${WAVE}"/>
                    <path class="wave front" d="${WAVE}" fill="url(#grad-${name})"/>
                </g>
            </g>
            <circle class="rim" cx="24" cy="24" r="21.4"/>
        </svg>`;
}

function build(config) {
    hud.innerHTML = '';
    Object.keys(items).forEach((name) => delete items[name]);

    const style = ['ring', 'liquid', 'segments'].includes(config.style) ? config.style : 'ring';

    lowThreshold = config.low ?? 20;
    animations = config.animations !== false;
    segmented = style === 'segments';
    hud.dataset.position = config.position || 'bottom-center';
    hud.dataset.style = style;
    document.documentElement.style.setProperty('--scale', config.scale || 1);
    document.body.classList.toggle('no-anim', !animations);

    let index = 0;

    (config.order || Object.keys(config.statuses)).forEach((name) => {
        const status = config.statuses[name];
        if (!status || !status.enabled || !ICONS[name]) return;

        const color = status.color || '#ffffff';
        const color2 = lighten(color, 0.5);

        const el = document.createElement('div');
        el.className = 'status hidden';
        el.style.setProperty('--color', color);
        el.style.setProperty('--color2', color2);
        el.style.setProperty('--i', index++);

        const gauge = style === 'liquid'
            ? liquidMarkup(name, color, color2)
            : ringMarkup(name, color, color2, style === 'segments');

        el.innerHTML = `
            <div class="orb">
                ${gauge}
                <svg class="icon" viewBox="0 0 24 24">${ICONS[name]}</svg>
            </div>
            ${config.percent ? '<div class="percent">0</div>' : ''}
        `;

        const orb = el.querySelector('.orb');
        orb.addEventListener('animationend', (event) => {
            if (event.target === orb) orb.classList.remove('hit', 'gain');
        });

        hud.appendChild(el);
        items[name] = {
            el,
            orb,
            icon: el.querySelector('.icon'),
            label: el.querySelector('.percent'),
            ringValue: el.querySelector('.gauge.ring .value'),
            level: el.querySelector('.gauge.liquid .level'),
            previous: null,
            dead: false,
        };
    });
}

function react(item, type) {
    item.orb.classList.remove('hit', 'gain');
    void item.orb.offsetWidth; // relance l'animation
    item.orb.classList.add(type);
}

// value : nombre de 0 a 100, ou false pour cacher le cercle
function setStatus(name, value) {
    const item = items[name];
    if (!item) return;

    if (value === false || value === null || value === undefined) {
        item.el.classList.add('hidden');
        item.el.classList.remove('low', 'dead');
        item.previous = null;
        return;
    }

    const percent = Math.max(0, Math.min(100, Math.round(value)));
    const dead = name === 'health' && percent <= 0;

    if (item.ringValue) {
        // Arc continu, y compris en style 'segments' : le dernier cran raccourcit petit a petit
        const shown = percent / 100;
        item.ringValue.style.strokeDashoffset = CIRCUMFERENCE * (1 - shown);
    }
    if (item.level) {
        item.level.style.transform = `translateY(${46 - 45 * (percent / 100)}px)`;
    }
    if (item.label) {
        item.label.textContent = percent;
    }

    item.el.classList.remove('hidden');
    item.el.classList.toggle('dead', dead);
    item.el.classList.toggle('low', !dead && percent <= lowThreshold);

    if (dead !== item.dead) {
        item.dead = dead;
        item.icon.innerHTML = dead ? SKULL : ICONS[name];
    }

    // Reactions : secousse rouge quand on perd de la vie / armure, halo quand on se soigne, mange ou boit
    if (animations && item.previous !== null) {
        const delta = percent - item.previous;
        const damageable = name === 'health' || name === 'armor';
        const gainable = damageable || name === 'hunger' || name === 'thirst';

        if (damageable && delta <= -3) react(item, 'hit');
        else if (gainable && delta >= 5) react(item, 'gain');
    }

    item.previous = percent;
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};

    if (msg.action === 'config') {
        build(msg);
    } else if (msg.action === 'update') {
        Object.entries(msg.data || {}).forEach(([name, value]) => setStatus(name, value));
    } else if (msg.action === 'anchor') {
        const root = document.documentElement.style;
        root.setProperty('--map-left', Number(msg.left) || 0);
        root.setProperty('--map-bottom', Number(msg.bottom) || 0);
        root.setProperty('--map-width', Number(msg.width) || 25);
    } else if (msg.action === 'visible') {
        hud.classList.toggle('visible', !!msg.state);
    }
});

if (inGame) {
    fetch(`https://${GetParentResourceName()}/ready`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: '{}',
    }).catch(() => {});
} else {
    // -----------------------------------------------------------------------
    // Apercu : ouvre html/index.html dans un navigateur pour regler le style
    // sans lancer le jeu. Touches 1 / 2 / 3 : style, P : pourcentages, M : position.
    // -----------------------------------------------------------------------
    const params = new URLSearchParams(location.search);
    const styles = ['ring', 'liquid', 'segments'];
    const positions = ['bottom-center', 'minimap', 'bottom-right'];

    const preview = {
        position: params.get('position') || 'bottom-center',
        style: params.get('style') || 'segments',
        percent: params.get('percent') === '1',
        scale: Number(params.get('scale')) || 1,
        low: 20,
        animations: true,
        order: ['health', 'armor', 'hunger', 'thirst', 'stamina', 'oxygen'],
        statuses: {
            health: { enabled: true, color: '#ff4d5e' },
            armor: { enabled: true, color: '#4d9dff' },
            hunger: { enabled: true, color: '#ffa63d' },
            thirst: { enabled: true, color: '#3dd6ff' },
            stamina: { enabled: true, color: '#9be15d' },
            oxygen: { enabled: true, color: '#b79dff' },
        },
    };

    const demo = { health: 82, armor: 55, hunger: 64, thirst: 14, stamina: 90, oxygen: 70 };

    const render = () => {
        build(preview);
        Object.entries(demo).forEach(([name, value]) => setStatus(name, value));
        hud.classList.remove('visible');
        void hud.offsetWidth;
        hud.classList.add('visible');
    };

    document.body.classList.add('preview');

    if (params.get('help') !== '0') {
        const help = document.createElement('div');
        help.className = 'preview-help';
        help.innerHTML = '<b>1</b><b>2</b><b>3</b> style &nbsp; <b>P</b> pourcentages &nbsp; <b>M</b> position &nbsp; <b>D</b> dégâts &nbsp; <b>S</b> soin';
        document.body.appendChild(help);
    }

    window.addEventListener('keydown', (event) => {
        const key = event.key.toLowerCase();

        if (['1', '2', '3'].includes(key)) {
            preview.style = styles[Number(key) - 1];
            render();
        } else if (key === 'p') {
            preview.percent = !preview.percent;
            render();
        } else if (key === 'm') {
            preview.position = positions[(positions.indexOf(preview.position) + 1) % positions.length];
            render();
        } else if (key === 'd') {
            demo.health = Math.max(0, demo.health - 18);
            setStatus('health', demo.health);
        } else if (key === 's') {
            demo.health = Math.min(100, demo.health + 25);
            setStatus('health', demo.health);
        }
    });

    render();
}
