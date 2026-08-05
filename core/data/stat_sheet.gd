class_name StatSheet
extends Resource

## The player-facing stat list, as authored order rather than enum order.
##
## The enum is APPEND-ONLY, so its order is a history of when things were added
## and says nothing about how they should be read. This is the reading order.
##
## Why a resource holding the list rather than scanning content/stats/ at
## runtime: a directory scan is "drop a file in and it appears", which sounds
## better until an exported build reorders or trims the pack. An explicit list
## plus a validator rule that every stat is in it is the same guarantee, checked
## a second before it can ship instead of a second after.

@export var entries: Array[StatMetadata] = []

## What the stat sheet shows, in reading order. New stats appear here the moment
## their metadata is authored and added - nothing in the UI enumerates stats
## itself, so no screen has to be touched.
func visible_sorted() -> Array[StatMetadata]:
	var shown: Array[StatMetadata] = []
	for entry in entries:
		if entry != null and entry.visible_in_ui:
			shown.append(entry)

	shown.sort_custom(func(a: StatMetadata, b: StatMetadata) -> bool:
		return a.sort_order < b.sort_order
	)
	return shown

func metadata_for(stat: StatTypes.Stat) -> StatMetadata:
	for entry in entries:
		if entry != null and entry.stat == stat:
			return entry
	return null
