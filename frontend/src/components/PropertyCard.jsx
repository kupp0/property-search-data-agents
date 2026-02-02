import React from 'react';

const PropertyCard = React.memo(({ listing }) => {
    return (
        <div className="bg-white dark:bg-slate-800 rounded-xl overflow-hidden shadow-sm hover:shadow-md transition-all border border-slate-100 dark:border-slate-700 group">
            <div className="relative h-48 overflow-hidden bg-slate-100 dark:bg-slate-900">
                {listing.image_gcs_uri ? (
                    <img
                        src={listing.image_gcs_uri}
                        alt={listing.title}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                        loading="lazy"
                    />
                ) : (
                    <div className="w-full h-full flex items-center justify-center text-slate-400">
                        <span className="text-xs">No Image</span>
                    </div>
                )}
                <div className="absolute top-2 right-2 bg-black/50 backdrop-blur-md text-white px-2 py-1 rounded-md text-xs font-bold">
                    CHF {listing.price}
                </div>
            </div>
            <div className="p-4">
                <h3 className="font-bold text-slate-800 dark:text-slate-100 text-sm mb-1 line-clamp-1" title={listing.title}>
                    {listing.title}
                </h3>
                <div className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400 mb-3">
                    <span>{listing.bedrooms} Beds</span>
                    <span>•</span>
                    <span>{listing.city}, {listing.canton}</span>
                    <span className="hidden sm:inline">• {listing.country}</span>
                </div>
                <p className="text-xs text-slate-600 dark:text-slate-400 line-clamp-2 leading-relaxed">
                    {listing.description}
                </p>
            </div>
        </div>
    );
});

export default PropertyCard;
