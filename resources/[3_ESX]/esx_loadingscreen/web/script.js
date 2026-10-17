/* =========================================================
   NOVYRA STUDIO — Loading Screen
   ---------------------------------------------------------
   Tout ce qui est modifiable se trouve dans CONFIG.
   ========================================================= */
const CONFIG = {
    serverName: 'NOVYRA STUDIO',
    tagline: 'Roleplay · ESX',

    // Liens affichés en bas à droite (laisser [] pour les masquer)
    links: [
        { type: 'discord', label: 'DISCORD', value: 'discord.gg/novyra' },
        { type: 'web',     label: 'BOUTIQUE', value: 'novyra.tebex.io' }
    ],

    // Étapes (texte principal) selon l'avancement
    steps: [
        'Initialisation des systèmes',
        'Connexion au serveur',
        'Téléchargement des ressources',
        'Chargement des scripts',
        'Préparation de la ville',
        'Dernières vérifications'
    ],

    tips: [
        'Appuie sur F1 pour ouvrir le menu d\'aide.',
        'Utilise /report pour contacter le staff.',
        'Passe au Pôle Emploi pour trouver un travail.',
        'Ouvre ton inventaire avec TAB.',
        'Ton téléphone te permet d\'appeler les autres joueurs.',
        'Respecte le code de la route pour éviter les amendes.',
        'Blessé ? Rends-toi à l\'hôpital le plus proche.',
        'Dépose ton argent à la banque pour le garder en sécurité.'
    ],

    tipInterval: 6000,   // ms
    starCount: 140
}

/* ---------- Icônes ---------- */
const ICONS = {
    discord: '<svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M19.5 5.3A17 17 0 0 0 15.3 4l-.5 1a15.6 15.6 0 0 0-5.6 0l-.5-1a17 17 0 0 0-4.2 1.3C1.8 9.3 1.1 13.2 1.4 17a17 17 0 0 0 5.2 2.6l1.1-1.8c-.6-.2-1.2-.5-1.8-.9l.4-.3a12.2 12.2 0 0 0 11.4 0l.4.3c-.6.4-1.2.7-1.8.9l1.1 1.8a17 17 0 0 0 5.2-2.6c.4-4.4-.7-8.3-3.1-11.7zM8.7 14.7c-1 0-1.9-1-1.9-2.1s.8-2.1 1.9-2.1 1.9 1 1.9 2.1-.8 2.1-1.9 2.1zm6.6 0c-1 0-1.9-1-1.9-2.1s.8-2.1 1.9-2.1 1.9 1 1.9 2.1-.8 2.1-1.9 2.1z"/></svg>',
    web: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>'
}

/* ---------- État ---------- */
const state = {
    current: 0,
    target: 0,
    tipIndex: 0,
    lastStep: -1,
    complete: false,
    closing: false
}

const $ = (id) => document.getElementById(id)
let el = {}

/* ---------- Initialisation UI ---------- */
function initUI() {
    el = {
        bar: $('progressBar'),
        pct: $('progressPercentage'),
        step: $('loadingStep'),
        text: $('loadingText'),
        log: $('progressStatus'),
        tip: $('tipText'),
        pager: $('tipPager'),
        links: $('links'),
        clock: $('clock')
    }

    $('serverName').textContent = CONFIG.serverName
    $('serverTagline').textContent = CONFIG.tagline

    // Liens
    el.links.innerHTML = CONFIG.links.map(l => `
        <div class="link">
            ${ICONS[l.type] || ICONS.web}
            <div><small>${l.label}</small>${l.value}</div>
        </div>`).join('')

    // Astuces
    el.pager.innerHTML = CONFIG.tips.map((_, i) => `<span class="${i === 0 ? 'on' : ''}"></span>`).join('')
    el.tip.textContent = CONFIG.tips[0] || ''

    // Horloge
    const tick = () => {
        const d = new Date()
        el.clock.textContent = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
    }
    tick()
    setInterval(tick, 10000)
}

/* ---------- Progression ---------- */
function render() {
    const diff = state.target - state.current
    state.current = Math.abs(diff) > 0.05 ? state.current + diff * 0.07 : state.target

    const p = Math.min(Math.floor(state.current), 100)
    el.bar.style.width = `${state.current}%`
    el.pct.textContent = p

    const stepIndex = Math.min(Math.floor((p / 100) * CONFIG.steps.length), CONFIG.steps.length - 1)
    if (stepIndex !== state.lastStep && p < 100) {
        state.lastStep = stepIndex
        el.step.textContent = `ÉTAPE ${stepIndex + 1}/${CONFIG.steps.length}`
        swapText(el.text, CONFIG.steps[stepIndex] + '...')
    }

    if (p >= 100 && !state.complete) {
        state.complete = true
        el.step.textContent = 'TERMINÉ'
        swapText(el.text, `Bienvenue sur ${CONFIG.serverName}`)
        el.log.textContent = 'Entrée en ville...'
        notifyComplete()
    }

    requestAnimationFrame(render)
}

function swapText(node, value) {
    node.style.opacity = '0'
    setTimeout(() => { node.textContent = value; node.style.opacity = '1' }, 200)
}

function setProgress(fraction) {
    // la progression ne recule jamais
    state.target = Math.max(state.target, Math.min(Math.max(fraction * 100, 0), 100))
}

function notifyComplete() {
    if (typeof GetParentResourceName !== 'function') return
    fetch(`https://${GetParentResourceName()}/loadingComplete`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}'
    }).catch(() => {})
}

function close() {
    if (state.closing) return
    state.closing = true
    setProgress(1)
    document.getElementById('app').classList.add('is-closing')
}

/* ---------- Astuces ---------- */
function rotateTips() {
    if (CONFIG.tips.length < 2) return
    el.tip.classList.add('is-out')
    setTimeout(() => {
        state.tipIndex = (state.tipIndex + 1) % CONFIG.tips.length
        el.tip.textContent = CONFIG.tips[state.tipIndex]
        el.tip.classList.remove('is-out')
        ;[...el.pager.children].forEach((s, i) => s.classList.toggle('on', i === state.tipIndex))
    }, 450)
}

/* ---------- Champ d'étoiles ---------- */
function initStars() {
    const canvas = $('stars')
    const ctx = canvas.getContext('2d')
    const colors = ['#2ee6ff', '#3d5bff', '#a35cff', '#ffffff']
    let w, h, stars = []

    const resize = () => {
        w = canvas.width = window.innerWidth
        h = canvas.height = window.innerHeight
    }

    const spawn = (randomY = true) => ({
        x: Math.random() * w,
        y: randomY ? Math.random() * h : h + 10,
        r: Math.random() * 1.6 + 0.3,
        vy: Math.random() * 0.35 + 0.08,
        vx: (Math.random() - 0.5) * 0.08,
        a: Math.random() * 0.6 + 0.2,
        tw: Math.random() * Math.PI * 2,
        c: colors[(Math.random() * colors.length) | 0]
    })

    resize()
    window.addEventListener('resize', resize)
    stars = Array.from({ length: CONFIG.starCount }, () => spawn(true))

    const loop = () => {
        ctx.clearRect(0, 0, w, h)
        for (const s of stars) {
            s.y -= s.vy
            s.x += s.vx
            s.tw += 0.03
            if (s.y < -10) Object.assign(s, spawn(false))

            ctx.globalAlpha = s.a * (0.6 + 0.4 * Math.sin(s.tw))
            ctx.fillStyle = s.c
            ctx.shadowBlur = s.r * 6
            ctx.shadowColor = s.c
            ctx.beginPath()
            ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2)
            ctx.fill()
        }
        requestAnimationFrame(loop)
    }
    loop()
}

/* ---------- Events FiveM ---------- */
const handlers = {
    loadProgress(data) {
        if (typeof data.loadFraction === 'number') setProgress(data.loadFraction)
    },
    onLogLine(data) {
        if (data.message) el.log.textContent = data.message.replace(/\.\.\.$/, '') + '...'
    },
    'novyra:close'() {
        close()
    }
}

window.addEventListener('message', (e) => {
    const data = e.data
    if (!data || typeof data !== 'object') return
    const fn = handlers[data.eventName]
    if (fn) fn(data)
})

/* ---------- Démarrage ---------- */
window.addEventListener('DOMContentLoaded', () => {
    initUI()
    initStars()
    requestAnimationFrame(render)
    setInterval(rotateTips, CONFIG.tipInterval)

    // Aperçu dans un navigateur classique (hors FiveM) : simulation du chargement
    if (typeof GetParentResourceName !== 'function') {
        let f = 0
        const sim = setInterval(() => {
            f += Math.random() * 0.06
            setProgress(f)
            if (f >= 1) clearInterval(sim)
        }, 300)
    }
})
