class_name ShopListing
extends Resource
## The shop page of one catalog item (docs/HARDWARE_CATALOG.md §4): long title, selling points,
## long description and customer reviews. The store and the reviews are fictional. Technical
## figures shown in the specs table come from the HardwareDefinition, never from here, so the
## page cannot disagree with the simulation; the rating is the average of the reviews listed.
## One `.tres` per purchasable item in res://data/shop/ (file name = item id).

@export var item_id: StringName = &""
@export var title: String = "" ## Long title, as online stores write them.
@export var bullets: PackedStringArray = PackedStringArray() ## "Acerca de este producto".
@export_multiline var description: String = ""
## {"author": String, "stars": int 1–5, "title": String, "text": String, "date": String,
##  "verified": bool}
@export var reviews: Array[Dictionary] = []


## Average of the listed reviews (0 if none), e.g. 4.4.
func rating() -> float:
	if reviews.is_empty():
		return 0.0
	var total := 0
	for review: Dictionary in reviews:
		total += int(review["stars"])
	return float(total) / reviews.size()


## How many listed reviews give `stars` stars.
func count_with(stars: int) -> int:
	var n := 0
	for review: Dictionary in reviews:
		if int(review["stars"]) == stars:
			n += 1
	return n


## Rule violations of this listing (empty = valid).
func problems() -> Array[String]:
	var result: Array[String] = []
	var tag := String(item_id)
	if title.strip_edges() == "" or description.strip_edges() == "":
		result.append("%s: listing needs a title and a description" % tag)
	if bullets.size() < 3:
		result.append("%s: listing needs at least 3 bullets" % tag)
	if reviews.size() < 3:
		result.append("%s: listing needs at least 3 reviews" % tag)
	for review: Dictionary in reviews:
		for key: String in ["author", "stars", "title", "text", "date", "verified"]:
			if not review.has(key):
				result.append("%s: review without %s" % [tag, key])
		var stars := int(review.get("stars", 0))
		if stars < 1 or stars > 5:
			result.append("%s: review stars must be 1..5" % tag)
	return result
