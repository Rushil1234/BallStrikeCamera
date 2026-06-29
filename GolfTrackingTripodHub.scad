// Golf Tracking Tripod Hub
// Modular, field-stakeable hub: a real tripod (raised hub on three splayed legs +
// optional ground spike), a sealed battery/wiring core with an NFC tap zone, a
// downward LED light bar with glare hood, a side OLED screen, and a phone rest
// with a sun-shade canopy. Fully parametric / OpenSCAD-Customizer ready.
//
// Coordinate convention:  +Z up,  -Z stake,  +Y front (light),
//                         -Y back (phone),  +X right (OLED).
// Every sub-part overlaps its neighbour by `eps` so the union resolves to one
// manifold (watertight) mesh for STL export.

// === Render Options ===
show_base        = true;   // Show the tripod base (hub + legs + stake)
show_core        = true;   // Show the battery/wiring core housing
show_light       = true;   // Show the LED light bar + OLED screen mount
show_phone       = true;   // Show the phone rest + canopy deck
explode          = false;  // Separate the modules for inspection

// === Tripod Base ===
hub_radius        = 20;    // [10:50] Central hub radius (mm)
hub_height        = 30;    // [15:80] Hub height where legs meet & the core sits (mm)
leg_count         = 3;     // [3:6] Number of tripod legs
leg_length        = 150;   // [80:260] Length of each splayed leg (mm)
leg_splay         = 26;    // [10:45] Leg splay angle from vertical (deg)
leg_width         = 18;    // [10:40] Leg width at the hub (in the bending plane, mm)
leg_thick         = 14;    // [8:30] Leg thickness at the hub (tangential, mm)
leg_taper         = 0.6;   // [0.3:0.05:1] Foot size as a fraction of the hub size
foot_diameter     = 26;    // [12:50] Ground foot-pad diameter (mm)
foot_height       = 4;     // [2:12] Foot-pad height (mm)
include_stake     = true;  // Add a central ground-anchor spike
stake_diameter    = 16;    // [6:30] Center stake thickness at the hub (mm)
stake_into_ground = 30;    // [0:80] How far the stake pokes below the feet (mm)

// === Core Housing ===
core_w           = 60;     // [40:120] Housing width X (mm)
core_d           = 60;     // [40:120] Housing depth Y (mm)
core_h           = 80;     // [40:160] Housing height Z (mm)
nfc_diameter     = 30;     // [15:50] NFC tap-zone indent diameter (mm)
nfc_depth        = 2;      // [0.5:0.5:5] NFC tap-zone indent depth (mm)
wire_channel_d   = 8;      // [4:20] Wiring pass-through diameter (mm)

// === Light Bar & OLED Mount ===
led_bar_w        = 50;     // [20:100] LED bar width (mm)
led_bar_h        = 15;     // [6:40] LED bar height (mm)
led_bar_depth    = 12;     // [6:40] LED shelf projection (mm)
led_mount_angle  = 45;     // [15:75] LED shelf downward tilt (deg)
hood_overhang    = 5;      // [0:20] Glare hood projection beyond the shelf (mm)
oled_w           = 30;     // [15:60] OLED active width (mm)
oled_h           = 20;     // [10:50] OLED active height (mm)
oled_recess      = 2;      // [0.5:0.5:5] Depth the glass sits into the bezel (mm)
bezel_frame      = 4;      // [2:10] Border width around the OLED window (mm)
bezel_depth      = 5;      // [3:15] How far the bezel stands proud (mm)

// === Phone Rest & Canopy ===
phone_width      = 80;     // [50:140] Backing plate / phone width (mm)
backing_height   = 150;    // [80:220] Backing plate height (mm)
phone_lip_d      = 10;     // [4:25] Bottom lip projection (mm)
phone_lip_h      = 12;     // [6:30] Bottom lip height (mm)
canopy_depth     = 100;    // [40:160] Sun-shade roof depth (mm)
canopy_thick     = 4;      // [2:10] Roof slab thickness (mm)
canopy_fascia_h  = 15;     // [0:40] Downturned front fascia height (mm)

// === Construction ===
wall_thickness   = 3;      // [1:0.5:8] General shell / bracket wall (mm)

// === Quality ===
$fn              = 100;    // [24:8:160] Curve smoothness

/* ---------------------------------------------------------------------------
   Derived values (not Customizer parameters)
--------------------------------------------------------------------------- */
eps           = 0.1;
tripod_top_z  = leg_length * cos(leg_splay);             // hub bottom height (feet at z = 0)
foot_radius   = hub_radius * 0.5 + leg_length * sin(leg_splay);  // foot stance radius
core_z0       = tripod_top_z + hub_height;              // housing floor Z
backing_thick = wall_thickness * 2;


// ===========================================================================
//  MODULE 1 — Base_And_Stake()
//  A real tripod: a raised central hub on `leg_count` splayed legs that reach
//  the ground on foot pads (feet at z = 0), plus an optional slender central
//  spike that anchors into the turf between the legs.
// ===========================================================================
module Base_And_Stake() {
    difference() {
        union() {
            // central hub the legs meet at and the core sits on
            translate([0, 0, tripod_top_z])
                cylinder(h = hub_height, r = hub_radius);

            // splayed legs reaching the ground
            for (i = [0 : leg_count - 1])
                rotate([0, 0, i * 360 / leg_count])
                    tripod_leg();

            // optional central ground-anchor spike, tapering to a point
            if (include_stake)
                translate([0, 0, -stake_into_ground])
                    cylinder(h = tripod_top_z + stake_into_ground,
                             r1 = 0, r2 = stake_diameter / 2);
        }
        // wiring passes down through the hub
        wiring_channel();
    }
}

// One splayed leg: a tapered rectangular beam, widest at the structural hub
// joint and narrowing to the foot. Built by aligning the extrude axis (+Z) to
// the hub->foot vector, so the leg stays rigid and reads like a real tripod leg.
// `leg_width` is the in-plane (bending) dimension; `leg_thick` is tangential.
module tripod_leg() {
    P_top  = [hub_radius - 2, 0, tripod_top_z + 2];  // anchored inside the hub
    P_foot = [foot_radius,    0, foot_height];        // lands on top of the foot
    d      = P_foot - P_top;
    L      = norm(d);
    ay     = atan2(d[0], d[2]);                       // tilt +Z onto the leg axis

    // tapered structural beam
    translate(P_top)
        rotate([0, ay, 0])
            linear_extrude(height = L, scale = leg_taper)
                square([leg_width, leg_thick], center = true);

    // foot: bridge the angled leg end down to a flat, grippy ground pad
    translate([foot_radius, 0, 0])
        hull() {
            translate([0, 0, foot_height]) sphere(d = leg_width * leg_taper);
            cylinder(h = foot_height, d = foot_diameter);
        }
}

// Vertical wiring pass-through: from the core cavity floor down through the hub
// (exits at the hub underside, between the legs). Stops below the top deck so
// the NFC face stays solid.
module wiring_channel() {
    translate([0, 0, tripod_top_z - eps])
        cylinder(h = hub_height + wall_thickness + 2 * eps, d = wire_channel_d);
}


// ===========================================================================
//  MODULE 2 — Core_Housing()
//  Hollow battery/wiring box on top of the hub; flat top deck with an NFC
//  tap-zone indent; a wiring channel is cut from the cavity down through the hub.
// ===========================================================================
module Core_Housing() {
    difference() {
        // outer body (overlaps the hub by eps for a clean weld)
        translate([-core_w / 2, -core_d / 2, core_z0 - eps])
            cube([core_w, core_d, core_h + eps]);

        // hollow interior for battery + electronics
        translate([-core_w / 2 + wall_thickness,
                   -core_d / 2 + wall_thickness,
                   core_z0 + wall_thickness])
            cube([core_w - 2 * wall_thickness,
                  core_d - 2 * wall_thickness,
                  core_h - 2 * wall_thickness]);

        // shallow NFC "tap zone" indent on the flat top deck
        translate([0, 0, core_z0 + core_h - nfc_depth])
            cylinder(h = nfc_depth + eps, d = nfc_diameter);

        // wiring channel from the cavity down through the hub
        wiring_channel();
    }
}


// ===========================================================================
//  MODULE 3 — Light_And_Screen_Mount()
//  Front: a tilted LED shelf (recessed for the bar) with a glare hood above.
//  Right: a raised bezel with a recess + window for an OLED module.
// ===========================================================================
module Light_And_Screen_Mount() {
    front_y = core_d / 2;
    led_z   = core_z0 + core_h * 0.42;

    // LED light bar shelf, tilted to face the ground
    translate([0, front_y - eps, led_z])
        rotate([led_mount_angle, 0, 0])
            led_shelf();

    // glare hood: a thin overhang above the light
    translate([0, front_y - eps, led_z + led_bar_h + wall_thickness])
        hood();

    // OLED bezel on the right (+X) face
    translate([core_w / 2 - eps, 0, core_z0 + core_h * 0.55])
        rotate([0, 90, 0])
            oled_bezel();
}

// Angled platform with a recess that retains the LED bar.
module led_shelf() {
    shelf_w     = led_bar_w + 2 * wall_thickness;
    shelf_depth = led_bar_depth + wall_thickness;
    difference() {
        translate([-shelf_w / 2, 0, -wall_thickness / 2])
            cube([shelf_w, shelf_depth, wall_thickness + led_bar_h]);
        translate([-led_bar_w / 2, -eps, wall_thickness / 2])
            cube([led_bar_w, led_bar_depth + eps, led_bar_h + eps]);
    }
}

// Flat overhang that blocks direct glare into the LED.
module hood() {
    translate([-(led_bar_w / 2 + wall_thickness), 0, 0])
        cube([led_bar_w + 2 * wall_thickness,
              led_bar_depth + hood_overhang,
              wall_thickness]);
}

// Raised frame with a recess + viewing window for an OLED module.
module oled_bezel() {
    frame_w = oled_w + 2 * bezel_frame;
    frame_h = oled_h + 2 * bezel_frame;
    win_w   = oled_w - 6;
    win_h   = oled_h - 6;
    difference() {
        translate([-frame_w / 2, -frame_h / 2, 0])
            cube([frame_w, frame_h, bezel_depth]);
        translate([-oled_w / 2, -oled_h / 2, bezel_depth - oled_recess])
            cube([oled_w, oled_h, oled_recess + eps]);
        translate([-win_w / 2, -win_h / 2, -eps])
            cube([win_w, win_h, bezel_depth + 2 * eps]);
    }
}


// ===========================================================================
//  MODULE 4 — Phone_And_Canopy_Deck()
//  Back: a tall phone backing plate with a retaining lip, plus a rigid canopy
//  roof that cantilevers back over the phone as a sun-shade.
// ===========================================================================
module Phone_And_Canopy_Deck() {
    back_y    = -core_d / 2;
    outer_y   = back_y - backing_thick;
    canopy_z  = core_z0 + backing_height - canopy_thick;
    canopy_y0 = outer_y - canopy_depth;

    // vertical backing plate (phone rest)
    translate([-phone_width / 2, outer_y + eps, core_z0])
        cube([phone_width, backing_thick, backing_height]);

    // bottom lip that catches the base of the phone
    translate([-phone_width / 2, outer_y - phone_lip_d + eps, core_z0])
        cube([phone_width, phone_lip_d, phone_lip_h]);

    // canopy roof: cantilevers back over the phone as a sun-shade
    translate([-phone_width / 2, canopy_y0 + eps, canopy_z])
        cube([phone_width, canopy_depth, canopy_thick]);

    // geometric downturned fascia at the front of the canopy
    translate([-phone_width / 2, canopy_y0 + eps, canopy_z - canopy_fascia_h])
        cube([phone_width, canopy_thick, canopy_fascia_h + canopy_thick]);
}


// ===========================================================================
//  ASSEMBLY
//  Union the selected modules, then cut the shared wiring channel once more so
//  it passes cleanly through housing + hub -> single manifold mesh.
//  `explode` offsets each module along Z/Y for visual inspection.
// ===========================================================================
module GolfTrackingTripodHub() {
    ex = explode ? 1 : 0;
    difference() {
        union() {
            if (show_base)  translate([0, 0, -40 * ex]) Base_And_Stake();
            if (show_core)  Core_Housing();
            if (show_light) translate([0,  40 * ex, 0]) Light_And_Screen_Mount();
            if (show_phone) translate([0, -40 * ex, 0]) Phone_And_Canopy_Deck();
        }
        if (!explode) wiring_channel();
    }
}

GolfTrackingTripodHub();
