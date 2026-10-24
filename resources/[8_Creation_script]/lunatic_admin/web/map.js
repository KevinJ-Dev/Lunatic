"use strict";

// ====================================================================
//  lunatic_admin — carte de Los Santos (Leaflet + tuiles satellite de map.gta.world)
//  Seule la carte est reprise : pas les marqueurs ni les données du site.
//  Les coordonnées sont celles du jeu : x vers l'est, y vers le nord (latitude = y, longitude = x).
// ====================================================================

const GTA_MAP_TILES = "https://map.gta.world/mapStyles/styleSatelite/{z}/{x}/{y}.jpg";

// Repère du jeu calé sur les tuiles (mêmes valeurs que map.gta.world)
const GTA_CRS = L.extend({}, L.CRS.Simple, {
    projection: L.Projection.LonLat,
    transformation: new L.Transformation(0.02072, 117.3, -0.0205, 172.8),
    scale: (zoom) => Math.pow(2, zoom),
    zoom: (scale) => Math.log(scale) / Math.LN2,
    infinite: true,
});

// Limites jouables (un peu de marge autour de l'île)
const GTA_BOUNDS = { minX: -5000, maxX: 5000, minY: -5000, maxY: 9000 };

// Crée une carte dans un élément (déjà dans la page ou non) ; renvoie de quoi y dessiner.
// options.onClick(x, y) : clic sur la carte en coordonnées du jeu.
function gtaMap(options = {}) {
    const el = h("div", { class: "gta-map" });
    const map = L.map(el, {
        crs: GTA_CRS,
        minZoom: 1,
        maxZoom: 7,
        zoomSnap: 0.5,
        attributionControl: true,
        maxBounds: [[GTA_BOUNDS.minY, GTA_BOUNDS.minX], [GTA_BOUNDS.maxY, GTA_BOUNDS.maxX]],
        maxBoundsViscosity: 0.8,
    });
    map.attributionControl.setPrefix(false);
    L.tileLayer(GTA_MAP_TILES, { minZoom: 0, maxZoom: 7, maxNativeZoom: 5, noWrap: true, attribution: "Carte : map.gta.world" }).addTo(map);
    map.setView([-400, 0], 2);

    const layer = L.featureGroup().addTo(map);
    let onClick = options.onClick || null;
    map.on("click", (e) => { if (onClick) onClick(e.latlng.lng, e.latlng.lat); });

    // Leaflet mesure sa taille à la création : à refaire quand l'élément change de place ou de taille
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(el);

    return {
        el,
        map,
        clear: () => layer.clearLayers(),
        // Mode « placer » : curseur en croix, le prochain clic donne une position
        setClick: (fn, picking) => { onClick = fn; el.classList.toggle("picking", !!picking); },
        // Zone circulaire (rayon en mètres du jeu)
        circle: (x, y, radius, style = {}, onSelect) => {
            const shape = L.circle([y, x], { radius, color: style.color || "#9650ff", weight: style.weight || 2, fillOpacity: style.fill ?? 0.25, dashArray: style.dashed ? "6 6" : null }).addTo(layer);
            if (style.label) shape.bindTooltip(style.label, { direction: "top", className: "gta-map-tip" });
            if (onSelect) shape.on("click", (e) => { L.DomEvent.stopPropagation(e); onSelect(); });
            return shape;
        },
        // Point (rond de couleur)
        point: (x, y, style = {}, onSelect) => {
            const dot = L.circleMarker([y, x], { radius: style.size || 6, color: "#fff", weight: 2, fillColor: style.color || "#9650ff", fillOpacity: 1 }).addTo(layer);
            if (style.label) dot.bindTooltip(style.label, { direction: "top", className: "gta-map-tip" });
            if (onSelect) dot.on("click", (e) => { L.DomEvent.stopPropagation(e); onSelect(); });
            return dot;
        },
        // Centre la carte sur une position du jeu
        // (taille remesurée d'abord : la carte vient souvent d'être remise dans la page ; sans animation, car une
        // animation interrompue par un nouvel affichage laissait les repères agrandis)
        focus: (x, y, zoom) => {
            map.invalidateSize(false);
            map.setView([y, x], zoom ?? Math.max(map.getZoom(), 4), { animate: false });
        },
        // Cadre l'ensemble de ce qui est dessiné
        fit: () => {
            map.invalidateSize(false);
            const bounds = layer.getBounds();
            if (bounds.isValid()) map.fitBounds(bounds, { padding: [30, 30], maxZoom: 4, animate: false });
        },
    };
}

// Une position cliquée sur la carte est-elle dans la zone jouable ?
function insideGtaMap(x, y) {
    return x >= GTA_BOUNDS.minX && x <= GTA_BOUNDS.maxX && y >= GTA_BOUNDS.minY && y <= GTA_BOUNDS.maxY;
}
