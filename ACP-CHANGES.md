# NifSkope R — collision editing for the Accurate Collision Project

A fork of [fo76utils/nifskope](https://github.com/fo76utils/nifskope), branched
from `develop` at `3797c89` (build of Nov 16 2026).

It adds two things:

1. **Havok collision shapes can be edited from the keyboard**, in small exact
   steps, without leaving NifSkope.
2. **Three headless command-line operations**, for editing meshes with no
   window open.

Nothing else is changed. No upstream behaviour is removed except one menu
shortcut, noted below.

## Why

Upstream already has mouse-drag transforms — hold **I**/**O**/**J**/**K** and
drag. They do not work on collision. `GLView::transformItem` rejects every bhk
block before doing anything:

```cpp
if ( !nif->blockInherits( iBlock, { "BSGeometry", "BSTriShape",
                                    "NiNode", "NiTriBasedGeom" } ) ) return;
```

No `bhk` type inherits from any of those, so `bhkConvexTransformShape`,
`bhkBoxShape`, `bhkCapsuleShape`, `bhkConvexVerticesShape` and
`bhkRigidBody`/`bhkRigidBodyT` all hit that early return. No message, no error —
the drag silently does nothing. Dragging the parent `NiNode` works, but it moves
the mesh along with the collision, so it cannot be used to fit one against the
other.

The drag transforms have a second limitation worth recording, because it makes
them look broken even on a mesh: `I`/`O`/`J`/`K` reach `kbdState` only through
`GLView::keyPressEvent`, and `GLView` is a `QWindow` set to `ClickFocus`. Unless
the viewport itself holds keyboard focus the modifier never arrives, so picking a
block in the Block List and then holding `O` does nothing. In practice the
feature is used by clicking the shape in the viewport, which selects it and
focuses the viewport in one action. That route is closed for collision blocks,
which viewport picking does not select — the same reason the nudge keys here are
routed through an application-level event filter instead.

The work this fork exists for is VR weapon collision, where shapes have to be
adjusted against the mesh by small amounts, repeatedly, and judged by eye. Mouse
dragging is the wrong instrument for that even where it works. Arrow keys with a
fixed step are exact and repeatable.

## Diagnostics

Set `NIFSKOPE_ACP_LOG` to a file path and the nudge writes one line per key
event and per edit to it: the key code and modifiers as Qt reports them, which
widget had focus, whether the nudge claimed the key, and for each write the
value before, the value written and the value read back from the model. With
the variable unset -- every normal run -- nothing is opened or formatted.

```powershell
$env:NIFSKOPE_ACP_LOG = "$env:TEMP\acp-nudge.log"; & "...\NifSkopeR.exe"
```

This exists because a reported "Shift+Y will not increase, only decrease" fault
turned out to be **keyboard ghosting, not a bug**. The log showed Shift+Y+Left
arriving 42 times and editing correctly, Alt+Y+Right arriving 42 times and
editing correctly, and Shift+Y+Right producing *no event of any kind* -- not
even the `ShortcutOverride` Qt sends before any shortcut can consume a press.
A key the process never receives cannot be a fault in the process. Most
keyboards block certain three-key combinations; the other Shift key, or Up
instead of Right, usually goes through.

Reach for this before theorising about the nudge again. Reasoning about the
code ruled out every candidate it could and still had the answer backwards;
one run of the log settled it in a minute.

## Controls

Select the collision block in the **Block List** first — `scene->currentBlock`
is what the feature acts on, and clicking in the viewport picks geometry, not
collision. Then hold a modifier and tap the arrow keys. Up/Right increases,
Down/Left decreases.

| hold | effect | block | step per tap |
|---|---|---|---|
| **R** | radius | `bhkCapsuleShape`, `bhkCylinderShape` | 0.0001 |
| **L** | length, both ends | `bhkCapsuleShape`, `bhkCylinderShape` | 0.0001 per end |
| **Shift + L** | length, first end only (`First Point` / `Vertex A`) | `bhkCapsuleShape`, `bhkCylinderShape` | 0.0001 |
| **Ctrl + L** | length, second end only (`Second Point` / `Vertex B`) | `bhkCapsuleShape`, `bhkCylinderShape` | 0.0001 |
| **W / L / H** | `Dimensions` X / Y / Z (half-extents) | `bhkBoxShape` | 0.0001 per side |
| **X / Y / Z** | translate along that axis | transform shapes, capsules, rigid bodies (cylinders below) | 0.0001 |
| **Shift + X / Y / Z** | rotate about that axis | transform shapes, capsules, rigid bodies — **not** cylinders | 0.01° |

**Capsules and cylinders share R and L**, but not position editing. Both are an
axis between two end points plus a radius, so the radius and length keys work on
either; the field names differ (`First Point`/`Second Point` against
`Vertex A`/`Vertex B`), which `AxisEnds` hides.

**A cylinder's position is edited per vertex.** `Vertex A` and `Vertex B` are
`Vector4`, and all four components are addressable:

| hold | effect | field |
|---|---|---|
| **X / Y / Z / W** | both vertices | `Vertex A` and `Vertex B` |
| **Shift + X / Y / Z / W** | first vertex only | `Vertex A` |
| **Alt + X / Y / Z / W** | second vertex only | `Vertex B` |

Three things follow from that, all deliberate:

* **W is overloaded.** It is the fourth component while a cylinder is selected,
  the box width while a `bhkBoxShape` is, and camera-forward otherwise. The
  selected block decides, in `eventFilter()`, so neither branch has to test for
  the other.
* **A cylinder has no rotate key.** Shift selects a vertex here, so it cannot
  also mean rotate. The cylinder branch in `nudgeApply()` sits before the
  Shift-rotate branch and returns, so a cylinder never reaches it.
* **Alt carries Vertex B, not Ctrl.** Ctrl+X, Ctrl+Y and Ctrl+Z are Cut,
  Redo and Undo; binding them shadowed all three while a cylinder was
  selected, which was not worth it. Alt+X/Y/Z/W collide with nothing, and a
  bare Alt still reaches the menu bar because only Alt *with* one of those
  keys is swallowed. Ctrl+L is unchanged — it is genuinely free.

The W component is one Havok ignores on a cylinder. It is written anyway,
because it is a real field visible in Block Details and nothing else in the
editor steps it. Everywhere else -- X/Y/Z moves, length, rotation -- W is read
back and written again unchanged rather than zeroed.

Hold an arrow past 0.35 s and it ramps: 30 steps/s doubling every 0.6 s, capped
at 1500 steps/s.

The keys work wherever focus is — Block List, Block Details or viewport.

### Units

**The step applies to the raw field value as shown in Block Details**, not to
world units. Those fields are Havok units, 1/69.99125 of world scale, so one
0.0001 tap is about 0.007 world units and the ramp tops out near 10.5 world
units/s. Editing the displayed number directly means there is no conversion to
get wrong: what you see change is exactly what the key moved.

### What each key writes

* **R** writes `Radius`, `Radius 1` **and** `Radius 2`. A capsule stores its
  radius three times and all three must agree, or the shape renders and collides
  inconsistently.
* **L** on a capsule slides the end points along the capsule's **own** axis,
  never a world axis, which is what keeps a tilted capsule tilted. Plain L moves
  both symmetrically about the midpoint. Shift and Ctrl pin one end and move the
  other, which necessarily shifts the midpoint — that is why plain L still exists
  beside them. The moved end is written from the pinned end plus the new length,
  so the pinned end stays bit-exact and the length never accumulates float drift
  along the axis. Holding Shift and Ctrl together does nothing rather than guess
  an end.
* **W / L / H** write `Dimensions`, which are **half-extents**: one tap moves the
  displayed number by 0.0001 and so grows the box by that much on each side,
  0.0002 overall, symmetrically about its own centre. A box has no position of
  its own, so to hold one face still you must move the parent transform shape
  too. L maps to Y because that is the long axis of a Skyrim weapon; nothing in
  the format itself calls an axis "length".
* **X / Y / Z** write the translation column of `Transform` for transform
  shapes, both end points together for a capsule, or `Translation` for anything
  else carrying one.
* **Shift + X / Y / Z** rotate. The delta is built with `fromEuler()` with
  exactly one non-zero angle — which for a single axis is unambiguous — and then
  **multiplied** into the stored rotation. Decomposing the stored rotation to
  Euler, changing one angle and recomposing would drift over repeated taps and
  would break at gimbal lock; multiplication cannot. A transform shape rotates
  its three basis columns and leaves the translation alone, so the shape spins in
  place instead of orbiting. A capsule swings both end points about their
  midpoint. A rigid body goes through `fromQuat` and `toQuat`.

Every edit clamps, so a radius, half-extent or length can never reach zero or
invert.

## Headless mode and the three CLI operations

Normally NifSkope is a window you click in. **Headless mode** — `--no-gui` plus
a command — runs the same program with no window: it opens the file, applies
one operation, saves and exits. Upstream added it in June 2026 and it is still
unreleased, present only in `develop` builds, which is why tagged NifSkope
releases ignore the flag.

What it buys you is that a mesh edit becomes something you can *type*, and so
something that can be run over a folder, scripted, or handed to an AI assistant
rather than performed by hand in the GUI. The work this fork exists for has
exactly that shape: hundreds of weapon meshes needing the same small edit.

This fork adds three operations to upstream's fourteen:

```
--SetEffectShaderEmission <path>   follows the named block's Shader Property
                                   link, requires a BSEffectShaderProperty,
                                   and zeroes Base Color RGB and Base Color
                                   Scale, keeping the colour alpha and the
                                   rest of the shader data
--RemoveBranch <path>              removes the named block and its
                                   descendants, then runs NifSkope's block
                                   reordering before saving.  Skips missing or
                                   duplicate names, non-removable blocks, and
                                   branches with shared descendants
--BlockName <name>                 names the target block for both of the
                                   above.  Exact and case-sensitive
```

Both take a NIF path or a folder processed recursively, and **overwrite input
files in place**. The motivating case was stripping ENB particle-light nodes
and their emission from Skyrim meshes.

Three traps worth stating plainly, because an assistant running these
unattended will hit all three:

* There is **no dry run and no backup**. A folder argument recurses. Point it
  at copies.
* `--BlockName` matching is exact and case-sensitive, and a near-miss **matches
  nothing rather than erroring**. It prints `Skipped (named block not found or
  name is ambiguous)` instead of `Saved (...)`, but **exits 0 either way**, so
  the exit code alone cannot distinguish a no-op from a successful edit. Capture
  stdout and check for `Saved`. Verified against the ALPHA 7.1 build.
* The exe is **GUI-subsystem**, so it cannot write to the console that launched
  it. Run it directly and `--no-gui` appears to do nothing. Redirect output to
  a file, or use a wrapper script.

These three were written by **Codex (OpenAI)**, not by Claude. They lived only
as an uncommitted working-tree edit plus a patched binary until being committed
to the `cli-headless-ops` branch.

## Rotation axes: R / P / Y are X / Y / Z

Block Details labels a rotation `R`, `P`, `Y`. Those are fed from
`toEuler(x, y, z)` in that order, so **R = X, P = Y, Y(aw) = Z**. Verified from
source rather than assumed: `fromEuler(x, 0, 0)` produces a pure X rotation, and
so on for the other two.

Note that the comment at `src/data/niftypes.h:1221` describes this with R and Y
swapped. The comment is wrong; the code is right.

## Implementation notes

Four things here were not obvious, and each cost a build to find.

**`GLView` is a `QOpenGLWindow`, not a widget.** It only receives key events
while the viewport itself has focus — but selecting a collision block puts focus
on the Block List. Without intervention the arrows moved the tree selection, and
holding a letter fired the tree's type-ahead search, which could change the
selected block out from under the edit. Fixed with an application-level event
filter (`qApp->installEventFilter`), which sees the keys wherever focus is.

**Window-level `QAction` shortcuts are dispatched before the focused widget sees
a key.** Bare `Z` was bound to View → Center Viewport, so Z did nothing while X
and Y worked. That one was fixed by deleting the shortcut from `nifskope.ui`; the
menu item itself remains. **This is the cruder of the two fixes, kept only
because it already shipped.** The better fix, used later for `L`, is to accept
`QEvent::ShortcutOverride`, which cancels the shortcut for that one keypress and
leaves it working the rest of the time. Use that for any future clash.

**Keys are claimed only when they would actually do something.** `L` is the Left
View shortcut and `W` is camera-forward; both keep working normally and are taken
over only while a block the nudge can edit is selected. `nudgeWouldClaim()`
answers that question for a key that is not yet held, which is what the
`ShortcutOverride` path needs.

**Ctrl needed a hole in the modifier guard.** The event filter passes Ctrl and
Alt straight through so menu commands keep working. Ctrl+L needed an exception,
kept deliberately narrow: Alt still bails unconditionally; the exception is
capsule-only, since allowing it on a box would make Ctrl+L there behave silently
like plain L; and Ctrl+arrow is taken only while an edit is live. Checked before
building that nothing is shadowed — NifSkope's only Ctrl bindings are `Ctrl+F9`,
`Ctrl+Alt+S` and the standard Undo/Redo/Save/New/Copy/Paste. Ctrl state is stored
in a member rather than read from the event, because `nudgeTick()` runs on the
frame loop and has no event to ask; it is assigned before any early return, and
on the release of Ctrl itself it is read from the key rather than from
`modifiers()`, which no longer reports a modifier that is being released.

### A trap worth repeating

`Matrix` is **row-major** `m[row][col]`. `Matrix4` is OpenGL **column-major**
`m[col][row]`, so a translation lives at `m[3][0..2]`. Mixing them up silently
transposes a rotation — no error, just a wrong result.

## Files changed

| file | change |
|---|---|
| `src/glview.h` | nudge key enum, step constants, ramp state, `eventFilter` declaration |
| `src/glview.cpp` | the whole feature: key mapping, event filter, `nudgeWouldClaim`, `nudgeActive`, `nudgeApply`, `nudgeTick`, frame-loop hook |
| `src/main.cpp` | window title: `NifSkope R` plus a build marker; and the three headless CLI operations |
| `src/ui/nifskope.ui` | removed the bare `Z` shortcut from `aViewCenter` |
| `NifSkope.pro` | `TARGET = NifSkopeR` |
| `acpbuild.sh` | build helper |

`src/glview.cpp` carries almost all of it and is the only substantial change.

## Telling builds apart

The title bar reads `NifSkope R …` and ends with a marker naming the feature
set, currently:

```
[ACP ALPHA 10 - nudge: R radius, L len (Shift/Ctrl one end), L/W/H box, X/Y/Z move + Shift rotate, cylinder X/Y/Z/W per vertex (Shift=A, Alt=B)]
```

If that marker is absent it is a stock build and none of this works. The marker
exists because a stock build and a fork build are otherwise indistinguishable on
screen, which wasted a test round early on.

`setApplicationName` is deliberately **not** changed — it keys the QSettings
path, and changing it would orphan existing settings.

## Building

Standard upstream build (MSYS2 UCRT64, qmake6, g++). Three traps, none of which
produces an error that points at its own cause:

1. **MSYS2's first launch** only runs its own setup and exits. Run it once and
   let it finish before trying to install anything.
2. **`COMSPEC` must be exported**, or qmake's compiler probes return empty and
   the build fails with no useful message.
3. **The build tree cannot live under a path containing spaces.** qmake emits a
   post-link step that leaves the project path unquoted.

Two DLLs the build does not deploy: `libz-1.dll` from the toolchain, and
`lib_coacd.dll`. CoACD is loaded at runtime by name rather than linked, so
nothing is missing at link time and the exe starts fine — the failure appears
only when a spell that uses convex decomposition runs, as "Failed to load CoACD
library". Copy it next to the exe; `QLibrary` searches the application directory.

Also note the target is `NifSkopeR`, with no space. A target named
`release/NifSkope R.exe` cannot work — it appears as a bare make target and make
splits targets on whitespace. The space exists only in the window title.

## Version history

| build | change |
|---|---|
| ALPHA 1 | first fork build; no feature yet |
| ALPHA 2 | arrow-key nudge: C radius, X/Y/Z translate; build marker added |
| ALPHA 3 | Shift + X/Y/Z rotation; renamed to NifSkope R |
| ALPHA 4 | keys claimed application-wide, so focus no longer matters |
| ALPHA 5 | `bhkBoxShape` dimensions on L / W / H |
| ALPHA 6 | radius moved from C to R; L lengthens a capsule |
| ALPHA 7 | Shift+L / Ctrl+L grow one end of a capsule |
| ALPHA 7.1 | headless CLI operations merged in from `cli-headless-ops` |
| ALPHA 8 | every capsule key applies to `bhkCylinderShape` too |
| ALPHA 9 | cylinder position edited per vertex: X/Y/Z/W, Shift = Vertex A, Ctrl = Vertex B |
| ALPHA 9.1 | fixed the camera spinning on after a nudge: claimed arrows no longer share the camera's rotate bits |
| ALPHA 10 | cylinder `Vertex B` moved from Ctrl to Alt, freeing Cut/Redo/Undo |

## Not done

* The mouse-drag path (`transformItem`) still rejects bhk blocks. Only the
  keyboard route was built.
* No undo integration. Upstream's drag transforms do not support undo either.

## Licence and attribution

Unchanged from upstream: the NifSkope 3-clause BSD licence in `LICENSE.md`.

The collision-editing changes were written by Claude (Anthropic) working with the
repository owner, over the build series above.
