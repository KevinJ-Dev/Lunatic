(() => {
    const $ = (id) => document.getElementById(id);
    const nv = $('nv');
    const btn = $('enter');

    const IN_GAME = typeof GetParentResourceName === 'function';
    const TAGS = {
        maj:    { label: 'Mise à jour', color: '#a78bfa' },
        event:  { label: 'Événement',   color: '#fbbf24' },
        info:   { label: 'Info',        color: '#38bdf8' },
        alerte: { label: 'Alerte',      color: '#f87171' },
    };

    const state = { open: false, busy: false, enterKey: true, name: '' };

    // ═════ utilitaires ═════
    const bind = (k, v) => document.querySelectorAll(`[data-bind="${k}"]`).forEach((el) => { el.textContent = v ?? ''; });
    const money = (n) => `${Math.round(Number(n) || 0).toLocaleString('fr-FR')} $`;
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const rgb = (hex) => {
        const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '');
        return m ? [1, 2, 3].map((i) => parseInt(m[i], 16)).join(', ') : null;
    };
    const setVar = (k, v) => document.documentElement.style.setProperty(k, v);

    const tick = () => {
        const d = new Date();
        $('clock').textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    };
    tick();
    setInterval(tick, 10000);

    function animateIn() {
        [...document.querySelectorAll('.nv-center > *')].forEach((el, i) => {
            el.classList.add('rise');
            el.style.transitionDelay = `${300 + i * 90}ms`;
        });
    }

    // ═════ rendu ═════
    function applyConfig(c = {}) {
        if (rgb(c.accent))  { setVar('--a1', c.accent);  setVar('--a1-rgb', rgb(c.accent)); }
        if (rgb(c.accent2)) { setVar('--a2', c.accent2); setVar('--a2-rgb', rgb(c.accent2)); }

        bind('serverName', c.serverName);
        bind('tagline', c.tagline);
        bind('discord', c.discord);
        $('discord').classList.toggle('is-hidden', !c.discord);
        $('info').classList.toggle('is-hidden', c.showInfo === false);
        nv.classList.toggle('no-bands', c.letterbox === false);
        state.enterKey = c.enterKey !== false;
        $('key').classList.toggle('is-hidden', !state.enterKey);

        // logo : image si fournie, sinon monogramme
        const logo = $('logo');
        if (c.logo) {
            logo.onload = () => { logo.hidden = false; $('monogram').style.display = 'none'; };
            logo.onerror = () => { logo.hidden = true; $('monogram').style.display = ''; };
            logo.src = c.logo;
        } else {
            logo.hidden = true;
            $('monogram').style.display = '';
        }

        const big = $('bigLogo');
        if (c.centerLogo) {
            big.onload = () => { big.hidden = false; };
            big.onerror = () => { big.hidden = true; };
            big.src = c.centerLogo;
        } else {
            big.hidden = true;
        }

        // actualités en défilement (dupliquées pour une boucle continue)
        const news = Array.isArray(c.news) ? c.news : [];
        $('ticker').classList.toggle('is-hidden', news.length === 0);
        const html = news.map((n) => {
            const t = TAGS[n.tag] || TAGS.info;
            return `<span class="nv-tick" style="--tc:${t.color};--tr:${rgb(t.color)}">
                <span class="nv-tag">${esc(t.label)}</span><b>${esc(n.title)}</b>${n.text ? ` — ${esc(n.text)}` : ''}
            </span>`;
        }).join('');
        $('tickerTrack').innerHTML = html + html;
        setVar('--tick', `${Math.max(20, news.length * 14)}s`);
    }

    function applyPlayer(p = {}) {
        state.name = p.name || '';
        bind('name', p.name || 'Citoyen');
        bind('job', p.job || 'Sans emploi');
        bind('location', p.location || 'Los Santos');
        bind('cash', money(p.cash));
        bind('bank', money(p.bank));
        bind('players', p.players ?? 0);
        bind('maxPlayers', p.maxPlayers ?? 0);
    }

    function setShot({ label, index = 1, total = 1 }) {
        const el = $('shotLabel');
        el.classList.add('is-swap');
        setTimeout(() => { el.textContent = label || ''; el.classList.remove('is-swap'); }, 300);

        const dots = $('dots');
        if (dots.children.length !== total) {
            dots.innerHTML = '<span class="nv-dot"></span>'.repeat(total);
        }
        [...dots.children].forEach((d, i) => d.classList.toggle('is-on', i === index - 1));
    }

    function open(data) {
        applyConfig(data.config);
        applyPlayer(data.player);
        animateIn();
        state.busy = false;
        btn.disabled = false;
        nv.classList.remove('is-leaving');
        requestAnimationFrame(() => nv.classList.add('is-open'));
        state.open = true;
    }

    function close() {
        nv.classList.remove('is-open', 'is-leaving');
        state.open = false;
    }

    async function enter() {
        if (!state.open || state.busy) return;
        state.busy = true;
        btn.disabled = true;
        nv.classList.add('is-leaving');

        if (!IN_GAME) {
            setTimeout(() => { close(); setTimeout(demo, 1400); }, 900);
            return;
        }

        try {
            const res = await fetch(`https://${GetParentResourceName()}/enter`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ name: state.name }),
            });
            const out = await res.json().catch(() => ({}));
            if (!res.ok || out.ok === false) throw new Error('entrée refusée');
            setTimeout(close, 700);
        } catch (e) {
            console.error('[novyra_spawn]', e);
            nv.classList.remove('is-leaving');
            state.busy = false;
            btn.disabled = false;
        }
    }

    // ═════ événements ═════
    window.addEventListener('message', ({ data }) => {
        if (!data || !data.action) return;
        if (data.action === 'open') open(data);
        else if (data.action === 'shot') setShot(data);
        else if (data.action === 'close') close();
    });

    btn.addEventListener('click', enter);
    window.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && state.enterKey) { e.preventDefault(); enter(); }
    });

    // ═════ aperçu hors jeu : ouvre index.html dans un navigateur ═════
    function demo() {
        open({
            config: {
                serverName: 'Novyra Studio', tagline: 'Roleplay · Los Santos', logo: 'img/emblem.png', centerLogo: 'img/logo.png',
                accent: '#22c7ff', accent2: '#8b4dff', discord: 'discord.gg/novyra',
                enterKey: true, showInfo: true, letterbox: true,
                news: [
                    { tag: 'maj', title: 'Mise à jour 2.4', text: 'Nouveau garage central et refonte des concessions' },
                    { tag: 'event', title: 'Rallye de Sandy Shores', text: "Départ samedi 21h à l'aérodrome" },
                    { tag: 'info', title: 'Recrutement LSPD', text: 'Candidatures ouvertes sur le Discord' },
                ],
            },
            player: { name: 'Tony Moreau', job: "Mécanicien · Chef d'atelier", location: 'Vinewood Blvd, Downtown Vinewood', cash: 4250, bank: 186400, players: 87, maxPlayers: 128 },
        });
        const shots = ['Vinewood Hills', 'Downtown Los Santos', 'Plage de Vespucci', 'Port de Los Santos'];
        let i = 0;
        const next = () => { if (!state.open) return; setShot({ label: shots[i], index: i + 1, total: shots.length }); i = (i + 1) % shots.length; };
        next();
        clearInterval(window.__nvDemo);
        window.__nvDemo = setInterval(next, 9000);
    }

    if (!IN_GAME) {
        document.body.classList.add('demo');
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('class', 'demo-city');
        svg.setAttribute('viewBox', '0 0 1600 400');
        svg.setAttribute('preserveAspectRatio', 'none');
        let x = 0, seed = 7, d = 'M0 400 ';
        const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280);
        while (x < 1600) {
            const w = 18 + rnd() * 44;
            const tall = x > 620 && x < 1080;
            const h = tall ? 150 + rnd() * 220 : 40 + rnd() * 110;
            d += `L${x} ${400 - h} L${x + w} ${400 - h} `;
            x += w + rnd() * 5;
        }
        svg.innerHTML = `<path d="${d}L1600 400 Z" fill="#0e0a16" opacity=".94"/>`;
        document.body.prepend(svg);
        demo();
    }
})();
