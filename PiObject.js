// Constructor
PiObject = function(o){
	
	// private variables
	// var this = this; // This is required, because of an ECMAScript bug, you can't use 'this' in an inner function.
	this._properties = [];
	this._values = {};
	this._length = this._properties.length;
	this._listeners = {};
	this._listeners[""] = []; // Init global listeners
	this._filters = {};
	this._filters[""] = []; // Init global filters
	this._uuid = null;
	this._uid = -1; // This is for generating unique property names.
	
	/* INITIALIZATION - Do This Last! */

	// Initialize Object
	this.init(o);
};
PiObject.prototype.getUUID = function() {
	if (this._uuid === null) {
		var my = {};
		my.date = new Date();
		my.uuid = [];
		my.uuid.push(my.date.getFullYear().toString());
		my.uuid.push(my.date.getMonth().toString());
		my.uuid.push(my.date.getDate().toString());
		my.uuid.push(my.date.getTime().toString());
		this._uuid = my.uuid.join("");
	}
	return this._uuid;
};

/* GET */

// Returns the total number of properties of this object.
PiObject.prototype.getLength = function() {
	return this._properties.length;
};

// Find the property name associated with a given index.
PiObject.prototype.getProperty = function(index) {
	if (index.constructor != Number) // string
		return index.replace(/^\s*(\S*)\s*$/,'$1');
	else if (index >= 0 && index < this.getLength())
		return this._properties[index];
	else
		return '';
};

// Converts property names to their numeric positions in the Array.
PiObject.prototype.getIndex = function(propertyName) {
	// Lookup by property name
	if (propertyName.constructor != Number) {
		for (var i=0; i < this.getLength(); i++)
			if (this._properties[i] === propertyName)
				return i;
	}
	// If not a property name, try treating it as a number.
	var num = parseInt(propertyName);
	if (propertyName === num) {
    	if (Math.abs(num) >=0 && Math.abs(num) < this.getLength())
    		return num;
	}
	return; // not found
};

// Without Argument: Returns a list of all of the property names of this object.
// With Argument: Returns a list of values that match the given property name for each child object contained within this object.
PiObject.prototype.getPropertyList = function(propertyName) {
	if (propertyName) {
		var value;
		var propertyList = [];
		for (var i=0; i<this._properties.length; i++) {
			value = this._values[this._properties[i]];
			if (value instanceof PiObject)
				propertyList.push( value.get(propertyName).toString() );
			else if (value instanceof Object) // Also works for Arrays
				propertyList.push( value[propertyName] || '' );
			else
				propertyList.push('');
		}
		return propertyList.join();
	}
	else {
		// Convert to a string so that we pass a copy of the array, instead of a reference to it.
		return this._properties.join();
	}
};

// Returns the value of a property, or the empty string if not found.
PiObject.prototype.get = function(property, defaultValue) {
	var my = {};
	
	if (typeof(property) === "string") {
		my.path = property.match(/[^\.\[\]]+/g);
		// Get property name from index, if numeric
		my.property = this.getProperty(my.path.shift());
	} else {
		my.path = [];
		my.property = this.getProperty(property);
	}
	// Get value from 'values' collection
	// CAUTION: You have to use typeof here, so that values of zero are not ignored.
	if (typeof this._values[my.property] !== "undefined")
		my.result = this._values[my.property];
	for (var p=0; p<my.path.length; p++) {
		if (typeof(my.result) !== "object")
			break;
		if (my.result instanceof PiObject) {
			my.index = my.result.getIndex(my.path[p]);
			my.result = my.result.get(my.index);
		}
		else if (my.result.constructor === Array) {
			my.index = parseInt(my.path[p]);
			if (my.path[p] == my.index) // CAUTION: type-insensitive comparison
				my.result = my.result[my.index];
			else
				delete my.result;
		}
		else if (typeof(my.result) === "object") {
			my.index = my.path[p];
			my.result = my.result[my.index];
		}
		else {
			break;
		}
	}
	// Apply filters
	my.filters = this._filters[property] || [];
	for (var i=0; i < my.filters.length; i++) {
		my.returnVariable = my.filters[i](this,property,my.result);
		if (typeof(my.returnVariable) !== "undefined")
			my.result = my.returnVariable;
	}
	// Apply default
	if (typeof(my.result) === "undefined")
		my.result = (typeof(defaultValue) !== "undefined") ? defaultValue : "";
	// Return result
	return my.result;
};

PiObject.prototype.exists = function(property) {
	// Get property name from index, if numeric
	property = this.getProperty(property);
	// Check existance
	if (property.length && this.getIndex(property) >= 0)
		return true;
	else
		return false;
};

/* SET */

// A function for direct assignment of properties, singly or in bulk.
PiObject.prototype.set = function(propertyName,value) {
	var o = {};
	// Convert arguments into an object
	if (typeof(propertyName) !== "undefined") {
		if (propertyName.constructor === Object)
			o = propertyName;
		else
			o[propertyName] = value;
	}
	// Process collection of name/value pairs.
	var my = {};
	for (my.name in o) {
		my.path = my.name.match(/[^\.\[\]]+/g);
		my.last = my.path.pop();
		if (my.path.length) {
			my.end = my.name.length - my.last.length;
			if (my.name.charAt(my.name.length-1) == ']')
				my.end -=  2;
			else
				my.end -= 1;
			my.path = my.name.substring(0, my.end);
			my.child = this.get(my.path);
			if (my.child) {
				if (my.child instanceof PiObject)
					my.child.set(my.last, o[my.name]);
				else if (my.child.constructor === Array)
					my.child[parseInt(my.last)] = o[my.name];
				else if (typeof(my.child) === "object")
					my.child[my.last] = o[my.name];
			}
		} else {
			my.name = my.last;
			my.index = my.name;
			// Named Property
			if (my.name.constructor === Number) // Numeric
				my.name = this.getProperty(my.name);
			// Old Value
			my.oldValue = this._values[my.name] || "";
			// Add New Property?
			if (typeof(this.getIndex(my.index)) === "undefined") {
				this._uid++;
				this._properties.push(my.name);
				this._length = this._properties.length;
			}
			// New Value
			my.newValue = o[my.name];
			this._values[my.name] = my.newValue;
			// Listeners
			my.listeners = this._listeners[my.name] || [];
			for (var i=0; i < my.listeners.length; i++) {
				my.result = my.listeners[i](this,my.index,my.oldValue,my.newValue);
				if (my.result != undefined && my.result != my.newValue) { // If no change, don't do a set, so we dont mess up deletes.
					my.newValue = my.result;
					this._values[my.name] = my.newValue;
				}
			}
		}
	}
	// If it's only a single set, return it as a convenience, to avoid "object.set(property,value); value = object.get(object.length);"  This replaces that with "value = object.set(property,value);"  We will only do this for the set operation with two arguments.  We will not do this when you pass a collection of properties (even if there is only one).
	if (propertyName != undefined && propertyName.constructor != Object)
		return this.get(propertyName); // Allow chaining
	else
		return this; // Allow chaining
};

// Insert values in the middle of the PiComponent's Array.
PiObject.prototype.insertAt = function(i) {
	var my = {};
	var o = {};
	my.index = this.getIndex(i);
	for (var i=1; i < arguments.length; i++) {
		my.prop = (++this._uid).toString();
		if (my.index >= 0)
			this._properties.splice(my.index++,0,my.prop);
		else
			this._properties.push(my.prop);
		this._length = this._properties.length;
		o[my.prop] = arguments[i];
	}
	return this.set(o); // Allow chaining
};

// Adds values to the end of a PiObject like an Array.
PiObject.prototype.add = function() {
	var my = {};
	var o = {};
	for (var i=0; i < arguments.length; i++) {
		my.prop = (++this._uid).toString();
		this._properties.push(my.prop);
		this._length = this._properties.length;
		o[my.prop] = arguments[i];
	}
	return this.set(o); // Allow chaining
};
PiObject.prototype.append = this.add;

/* MOVE */

// A special class of function that doesn't change the value of the property, but just reorders it, according to Array syntax.
// TO DO: I'm not sure if this should fire listeners.  The value is not changing, only it's location in the property array.
// So far, my only use is within a listener, to reorder new items after they are added.  I'm going to wait and see if I ever have to listen for this action before I fire any listeners in reaction to this function.
// Adding listeners here could profoundly change the game.  With a move, you must always check that the oldValue != newValue, which seems like a lot of extra code to use for every listener.
// Adding listeners here could profoundly change the game, since it is not an oldValue vs. newValue issue, but an oldIndex vs. newIndex issue.  My gut tells me that this doesn't fire any listeners.  Any designer using the move command should follow that up with the code in reaction to that move.
PiObject.prototype.move = function(oldIndex,newIndex) {
	var my = {};
	// Allows the use of negative indexes.
	// Make sure that if property names are used, they are converted into numerical indexes.
	oldIndex = this.getIndex(oldIndex);
    if (typeof(oldIndex) === "undefined")
		throw "index does not exist";
	// Make sure that if newIndex is a property it is converted into a numerical index.
	my.newIndex = this.getIndex(newIndex);
	if (typeof(my.newIndex) === "undefined") {
	 // Treat like an add operation
	    if (newIndex < 0)
	        newIndex = 0;
	    else
	        newIndex = this._properties.length;
	}
	// In case the designer is passing variables that just happend to evaluate to the same number, don't waste time on fake moves.
	if (oldIndex != newIndex) {
		my.prop = this._properties.splice(oldIndex,1)[0];
		if (newIndex < 0)
			newIndex++; // We need to shift negative indexes after removing an element, because they are not zero-based.
		if (newIndex >= this._properties.length)
			this._properties.push(my.prop);
		else
			this._properties.splice(newIndex,0,my.prop);
	}
	return this; // Allow chaining
};

/* DELETE */

// Removes the specified properties from the object.
PiObject.prototype.remove = function() {
	var my = {};
	var o = {};
	for (var i=0; i < arguments.length; i++) {
		// translate indexes into property names
		my.prop = this.getProperty(arguments[i]);
		// new value is empty string when calling listeners
		if (this._values[my.prop] != undefined)
			o[my.prop] = "";
	}
	this.set(o); // Let set call the listeners
	for (my.prop in o) {
		// get numeric index
		my.index = this.getIndex(my.prop);
		// check if delete has been overridden by a listener
		if (this._values[my.prop].length === 0) {
			delete this._values[my.prop]; // remove value
			this._properties.splice(my.index,1); // remove property
			this._length = this._properties.length;
		}
	}
	return this; // Allow chaining
};
PiObject.prototype["delete"] = this.remove; // alias

// WARNING: The point of this function is to clean out a PiObject, so it will ignore any listeners that restore values, and delete them anyway!!!
PiObject.prototype.removeAll = function() {
	for (var i=0; i < this._length; i++) {
		// Let set call the listeners
		this.set(i,"");
	}
	// But ignore any restored values, and delete all
	delete this._values;
	delete this._properties;
	this._values = {};
	this._properties = [];
	this._length=this._properties.length; // Do it this way, just to be sure.
	return this; // Allow chaining
};
PiObject.prototype.deleteAll = this.removeAll; // alias

/* FUNCTIONS */

// The core function for adding filters and listeners.
PiObject.prototype.addFunction = function(type,action,properties,method,applyToExisting) {
	var my = {};
	
	/* Error-Check Parameters */
	
	// Allow for assigning to multiple properties at once.
	// Multiple named properties can be supplied through a list of names, e.g. "prop1,prop3,prop5", or an array of names, e.g. ["prop1","prop3","prop4"].
	// Multiple indexes must be supplied through an array of indexes, e.g. [1,3,5], or else they will be assumed to be names, e.g. "1,3,5" == ["1","3","5"].
	// You can mix named and numbered properties through using an array, e.g. ["prop1",3,"prop5"].
	if (typeof(properties) === "string")
		properties = properties.split(",");
	
	// If properties not supplied, shift arguments to the right.
	if (typeof(properties) === "undefined" || properties.constructor !== Array) {
		applyToExisting = method;
		method = properties;
		properties = [""];
	}
	// Set default applyToExisting parameter
	if (typeof(applyToExisting) === "undefined" || typeof(applyToExisting) !== "boolean")
		applyToExisting = true;
	// Error Checking
	if (typeof(method) !== "function")
		throw("The method parameter supplied to the " + action + type + "() function was not of type 'function'.");
	if (properties.constructor !== Array)
		throw("The property parameter supplied to the " + action + type + "() function must be either of type 'string' or 'array'.");
	if (typeof(applyToExisting) !== "boolean")
		throw("The applyToExisting parameter supplied to the " + action + type + "() function was not of type 'boolean'.");
	
	// NOTE: The following will still only be executed once for global listeners/filters
	for (my.index=0; my.index<properties.length; my.index++) {
		
		// Get named property, if index provided
		my.property = this.getProperty(properties[my.index]);
		
		/* Add function */
		my.functions = (type === "Listener") ? this._listeners : this._filters;
		// Start each array with the existing global listeners.
		if (action === "add" && !my.functions[my.property])
			my.functions[my.property] = [].concat(my.functions[""]);
		
		if (my.property.length) {
			my.properties = [my.property];
		} else {
			my.properties = [];
			for (var p in my.functions)
				my.properties.push(p);
		}
		
		if (typeof(my.functions[my.property]) !== "undefined") { // only undefined if remove action
			my.alreadyExists = false;
			for (var p=0; p<my.properties.length; p++) {
				for (var i=my.functions[my.properties[p]].length-1; i >= 0; i--) {
					if (my.functions[my.properties[p]][i] === method) { // Do an exact match
						if (action === "add")
							my.alreadyExists = true;
						else if (action === "remove")
							my.functions[my.properties[p]].splice(i,1); // do remove
						break;
					}
				}
			}
			
			/* 
			 NOTE: I had considered applying to existing, even if it already exists, 
			 but only if the stored applyToExisting was false.  But we don't know 
			 enough.  It could have been stored, the value changed, and the function 
			 applied, but it still says applyToExisting is false.  We could update it 
			 when the function is fired, but what if it's global, then we have to track
			 What parameters it's been fired for.  Too difficult.  Keeping it simple. 
			*/ 
			if (action === "add" && !my.alreadyExists) {
				// NEW: all property function queues get an instantiation-ordered list of functions that include global functions.
				for (var i=0; i<my.properties.length; i++) {
					my.functions[my.properties[i]].push(method);
				}
				if (type === "Listener" && applyToExisting) {
					// This loop is all properties, not just function properties.
					if (!my.property.length)
						my.properties = this._properties;
					for (var i=0; i<my.properties.length; i++) {
						if (typeof(this._values[my.properties[i]]) !== "undefined") {
							my.result = method(this, my.properties[i], "", this._values[my.properties[i]]);
							if (typeof(my.result) !== "undefined")
								this._values[my.properties[i]] = my.result;
						}
					}
				}
			}
		}
		
	}
	return this; // Allow chaining
};

// Adds a listener function to either the entire object as a whole, or a specific property within the object.  
// NOTE: You may add a listener to property even if the property doesn't exist yet.  It will be fired when the property is added to the object.
PiObject.prototype.addListener = function(property,method,applyToExisting) {
	return this.addFunction.call(this,"Listener","add",property,method,applyToExisting);
};
// Removes a listener function from either the entire object, or from a specific property within the object.
PiObject.prototype.removeListener = function(property,method) {
	return this.addFunction.call(this,"Listener","remove",property,method);
};

// Adds a filter function to either the entire object as a whole, or a specific property within the object.
PiObject.prototype.addFilter = function(property,method) {
	return this.addFunction.call(this,"Filter","add",property,method);
};
// Removes a filter function from either the entire object, or from a specific property within the object.
PiObject.prototype.removeFilter = function(property,method) {
	return this.addFunction.call(this,"Filter","remove",property,method);
};

// Iterates over all values in the object and executes the passed-in function.
// This function was implemented such that execution is not broken, even if the function deletes items in the PiObject.
// If no value is returned by the method, then execution continues, but if any value is returned, the loop is broken and the value is returned to the caller.
PiObject.prototype.each = function(method) {
	if (typeof(method) !== "function")
		throw("The method parameter supplied to the each() function was not of type 'function'.");
	// Use propertyList, so that if the function deletes items within the object, we don't care about shifting.
	var propertyList = this.getPropertyList().split(',');
	// Iterate over properties
	for (var i=0; i<propertyList.length; i++) {
		// Make sure that the property hasn't been deleted by a previous iteration.
		if (typeof(this._values[propertyList[i]]) !== "undefined") {
			// CAUTION: The temptation here is to pass index as the second argument, instead of property.
			// However, if you do this, deleting items in the collection will break execution!
			// That's why we use property instead, plus for consistency so it exactly matches Filter functions.
			var result = method(this,propertyList[i],this._values[propertyList[i]]);
			if (result != undefined) {
				return result; // returning a value breaks the loop.
			}
		}
	}
};

/* End of Life */
PiObject.prototype.destroy = function() {
	delete this._properties;
	for (var prop in this._values)
		delete this._values[prop];
	delete this._values;
	delete this._length;
	for (var prop in this._listeners)
		for (var i in this._listeners[prop])
			delete this._listeners[prop][i];
	delete this._listeners;
	for (var prop in this._filters)
		for (var i in this._filters[prop])
			delete this._filters[prop][i];
	delete this._filters;
	delete this._uuid;
	delete this._uid;
};

// Static Functions
PiObject.prototype.init = function(o) {
	if (o instanceof Array)
		this.add.apply(this,o);
	else
		this.set.apply(this,arguments);
};

PiObject.extend=function(constructor) {
	var parent = this;
	constructor = constructor || function(){
		//this.parent = this.parent || parent.prototype; // Check for existance first, so you don't overwrite a child!!!
		parent.prototype.constructor.apply(this,arguments);
	};
	constructor.parent = parent.prototype;
	constructor.extend = PiObject.extend;
	constructor.prototype = new parent();
	constructor.prototype.constructor = constructor;
	return constructor;
};

/* DEBUG OUTPUT FUNCTIONS - These really shouldn't be used in regular code. */

PiObject.prototype.getValues = function(){
	// copy top-level items by value, and lower-level items by reference.
	var copy = {};
	for (var prop in this._values)
		copy[prop] = this._values[prop];
	return copy;
};