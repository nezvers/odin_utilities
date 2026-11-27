# quadtree: notes for agents

What is not obvious from the code of this library. The rules that hold for every library, the commands and the map of the libraries are in [../AGENTS.md](../AGENTS.md); the user facing description is in README.md.

- `quadtree.odin` (`Quadtree($E,$N,$L)`: elements in `hm.Static_Handle_Map`, `nodes` (root + groups of 4, freed groups linked through `first`), `links` (a leaf's elements, freed links linked through `next`); `Quadtree*` procs), `quadtree_test.odin` (`odin test quadtree`, a brute force comparison). Demos in `demo_common/` (collision, hover circles, bouncing balls), thin starters in `demo_raylib/` and `demo_karl2d/`. Reference port source: `references/quadtree` (git ignored, the C code; its clone URL over ssh does not work here, use https).
- A split cannot fail half way: `leafSplit` runs only when `L - links_in_use >= 3 * count` (worst case every element in four children, minus the links it frees) and a group of four nodes is free; the elements of a split are added without splitting again (`may_split = false`). A leaf that cannot split just holds more and tries again at the next add.
- `nodeAdd` that fails (links out) is undone with `nodeRemove`, which skips leaves that do not hold the element; so a failed `QuadtreeAdd` leaves the tree as it was (a split that happened stays, it is consistent).
- Removal and moving walk the tree with the rectangle STORED in the element, the same decisions as when it was added; never change `Element.rect` without removing first (`QuadtreeMove` does).
- Descent compares only against the centre of the node (`quadrants`), so rectangles outside of `bounds` land in the border leaves and are still found.
- Queries mark elements with `stamp` (an element sits in several leaves) instead of a temp buffer; the stamp counter wrap clears all marks.
- Demos: the script of each is run headless (`odin test quadtree/demo_common`) and in a window (`odin run quadtree/demo_karl2d -define:DEMO_TEST=true`, both pass). Circles and balls keep their data in fixed arrays and give `&array[i]` as `Element.ptr` (stable because the arrays never move).
