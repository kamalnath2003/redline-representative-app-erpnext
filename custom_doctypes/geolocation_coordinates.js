// Shared coordinate display for Geolocation fields on Sales Order and
// Customer Visit. The white card is added below each map when coordinates
// are present, without changing the stored Geolocation value.
(function () {
	if (window.__rcdGeolocationCoordinatesRegistered) return;
	window.__rcdGeolocationCoordinatesRegistered = true;

	function coordinatesFromValue(value) {
		if (!value) return null;

		var data = value;
		if (typeof data === 'string') {
			try {
				data = JSON.parse(data);
			} catch (e) {
				return null;
			}
		}

		var geometry = data && data.type === 'FeatureCollection'
			? data.features && data.features[0] && data.features[0].geometry
			: data && data.type === 'Feature'
				? data.geometry
				: data;
		var coords = geometry && geometry.coordinates;
		if (!Array.isArray(coords) || coords.length < 2) return null;

		// The RCD Sales app writes GeoJSON in standard [longitude, latitude] order.
		var longitude = Number(coords[0]);
		var latitude = Number(coords[1]);
		if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
		return { latitude: latitude, longitude: longitude };
	}

	function renderCoordinates(frm) {
		(frm.meta.fields || []).forEach(function (field) {
			if (field.fieldtype !== 'Geolocation') return;
			var fieldControl = frm.fields_dict[field.fieldname];
			var wrapper = fieldControl && fieldControl.$wrapper && fieldControl.$wrapper.get(0);
			if (!wrapper) return;

			var existing = wrapper.querySelector('.rcd-geolocation-coordinates');
			if (existing) existing.remove();

			var point = coordinatesFromValue(frm.doc[field.fieldname]);
			if (!point) return;

			var card = document.createElement('div');
			card.className = 'rcd-geolocation-coordinates';
			card.style.cssText = 'background:#fff;color:#222;border:1px solid #d8dee4;border-radius:6px;padding:10px 12px;margin-top:8px;font-size:13px;line-height:1.5;';
			card.textContent = 'Latitude: ' + point.latitude.toFixed(6) + '    Longitude: ' + point.longitude.toFixed(6);
			wrapper.appendChild(card);
		});
	}

	['Sales Order', 'Customer Visit'].forEach(function (doctype) {
		frappe.ui.form.on(doctype, {
			refresh: renderCoordinates
		});
	});
})();
