module main

type Fn = fn (mut node Node) !

[heap; params]
pub struct Node {
pub mut:
	id     string             [required]
	parent &Node = unsafe { nil }
	items  map[string][]&Node
	note   string
	funcs  map[string]Fn
	data   map[string]voidptr
	tags   []string
}

pub enum SearchDirection {
	up
	down
}

[params]
pub struct NodeSearchCriteria {
pub:
	id   string
	tags []string
	look SearchDirection = .down
}

pub fn (n Node) has_fn(key string) bool {
	if func := n.funcs[key] {
		if !isnil(func) {
			return true
		}
	}
	return false
}

pub fn (mut n Node) invoke_fn(key string) ! {
	if func := n.funcs[key] {
		if !isnil(func) {
			func(mut n)!
		} else {
			return error(@FN + ': function named "${key}" in node ${n.id} is nil')
		}
	} else {
		return error(@FN + ': no function named "${key}" in node ${n.id}')
	}
}

pub fn (mut n Node) add(item string, node &Node) {
	unsafe {
		node.parent = n
	}
	n.items[item] << node
}

pub fn (n &Node) is_leaf() bool {
	return n.items.len == 0
}

pub fn (n &Node) root() &Node {
	mut node := unsafe { n }
	for !isnil(node) {
		if isnil(node.parent) {
			return node
		}
		node = node.parent
	}
	return node
}

pub fn (n &Node) is_root() bool {
	return isnil(n.parent)
}

pub fn (n &Node) has_one_of_tags(tags []string) bool {
	for t in tags {
		if t in n.tags {
			return true
		}
	}
	return false
}

pub fn (n &Node) find_one_of_tags(tags []string) !string {
	for t in tags {
		if t in n.tags {
			return t
		}
	}
	return error('Node.find_one_of_tags: none of tags ${tags} found in ${n.tags}')
}

pub fn (n &Node) has_tags(tags []string) bool {
	for t in tags {
		if t !in n.tags {
			return false
		}
	}
	return true
}

pub fn (n Node) to_heap() &Node {
	return &Node{
		...n
	}
}

pub fn (n &Node) find_nearest(nsc NodeSearchCriteria) ?&Node {
	if nsc.id != '' && nsc.tags.len == 0 {
		return n.find_by_id(nsc.look, nsc.id)
	} else if nsc.id != '' && nsc.tags.len > 0 {
		return n.find_by_id_and_tags(nsc.look, nsc.id, nsc.tags)
	} else if nsc.id == '' && nsc.tags.len > 0 {
		return n.find_by_tags(nsc.look, nsc.tags)
	}
	return none
}

fn (n &Node) find_by_id(direction SearchDirection, id string) ?&Node {
	if n.id == id {
		return n
	}
	for _, items in n.items {
		for node in items {
			if isnil(node) {
				continue
			}
			if node.id == id {
				return node
			}
			if child := node.find_by_id(direction, id) {
				return child
			}
		}
	}
	return none
}

fn (n &Node) find_by_tags(direction SearchDirection, tags []string) ?&Node {
	if n.has_tags(tags) {
		return n
	}
	for _, items in n.items {
		// println('Looking at $k in $n.id $n.tags ($n.note)')
		for node in items {
			if isnil(node) {
				continue
			}
			if node.has_tags(tags) {
				return node
			}
			if child := node.find_by_tags(direction, tags) {
				return child
			}
		}
	}
	return none
}

fn (n &Node) find_by_id_and_tags(direction SearchDirection, id string, tags []string) ?&Node {
	if n.id == id && n.has_tags(tags) {
		return n
	}
	for _, items in n.items {
		// println('Looking at $k in $n.id $n.tags ($n.note)')
		for node in items {
			if isnil(node) {
				continue
			}
			if node.id == id && node.has_tags(tags) {
				return node
			}
			if child := node.find_by_id_and_tags(direction, id, tags) {
				return child
			}
		}
	}
	return none
}

pub fn as_heap(node Node) &Node {
	return &Node{
		...node
	}
}
