RTReorderableCollectionViewFlowLayout
=====================================
Forked from lxcid/LXReorderableCollectionViewFlowLayout

Extends `UICollectionViewFlowLayout` to support reordering of cells. Similar to long press and pan on books in iBook.

Features
========

The goal of RTReorderableCollectionViewFlowLayout is to allow reordering of collection view cells

 - Long press on cell begins reordering.
 - When reordering capability is invoked, fade the selected cell from highlighted to normal state.
 - Drag around the selected cell to move it to the desired location, the other cells adjust accordingly. Callback in the form of delegate methods are invoked.
 - Drag selected cell to the edges, depending on scroll direction, scroll in the desired direction.
 - Release to stop reordering.

Getting Started
===============

<img src="https://raw.github.com/lxcid/LXReorderableCollectionViewFlowLayout/master/Content/Screenshots/screenshot1.png" alt="Screenshot" title="Screenshot" style="display:block; margin: 10px auto 30px auto; width: 300px; height: 400px;" class="center">
