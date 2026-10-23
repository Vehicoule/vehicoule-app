//! One public call per capability; returned URLs are checked before the core sees them.

use contract::music::browse::{self, Category, CategoryPage, Release};
use contract::music::entity::{self, Entity, EntityPage};
use contract::music::lyrics::{self, Lyrics};
use contract::music::radio;
use contract::music::resolve::{self, ResolveRequest, Resolved};
use contract::music::search::{self, SearchRequest, SearchResults};
use contract::music::suggest;
use contract::types::{EntityRef, Image, Track, TrackQuery};

use crate::{CallError, Capability, Host, Plugin};

impl Host {
    pub async fn search(&self, p: &Plugin, req: SearchRequest) -> Result<SearchResults, CallError> {
        self.call(p, Capability::Search, async |store, instance| {
            search::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_search(store, &req).await
        })
        .await
    }

    pub async fn suggest(&self, p: &Plugin, prefix: &str, region: &str) -> Result<Vec<String>, CallError> {
        self.call(p, Capability::Suggest, async |store, instance| {
            suggest::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_suggest(store, prefix, region).await
        })
        .await
    }

    pub async fn fetch_entity(
        &self,
        p: &Plugin,
        target: EntityRef,
        region: &str,
        cursor: Option<String>,
    ) -> Result<EntityPage, CallError> {
        self.call(p, Capability::Entity, async |store, instance| {
            let guest = entity::GuestIndices::new(p.pre())?.load(&mut *store, instance)?;
            guest.call_fetch(store, &target, region, cursor.as_deref()).await
        })
        .await
    }

    pub async fn parse_link(&self, p: &Plugin, url: &str) -> Result<Option<EntityRef>, CallError> {
        self.call(p, Capability::Entity, async |store, instance| {
            entity::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_parse_link(store, url).await
        })
        .await
    }

    pub async fn resolve(&self, p: &Plugin, req: ResolveRequest) -> Result<Resolved, CallError> {
        self.call(p, Capability::Resolve, async |store, instance| {
            resolve::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_resolve(store, &req).await
        })
        .await
    }

    pub async fn lyrics(&self, p: &Plugin, track: TrackQuery) -> Result<Lyrics, CallError> {
        self.call(p, Capability::Lyrics, async |store, instance| {
            lyrics::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_fetch(store, &track).await
        })
        .await
    }

    pub async fn radio(&self, p: &Plugin, seed: TrackQuery, region: &str, limit: u32) -> Result<Vec<Track>, CallError> {
        self.call(p, Capability::Radio, async |store, instance| {
            radio::GuestIndices::new(p.pre())?.load(&mut *store, instance)?.call_radio(store, &seed, region, limit).await
        })
        .await
    }

    pub async fn browse_categories(
        &self,
        p: &Plugin,
        region: &str,
    ) -> Result<Vec<Category>, CallError> {
        self.call(p, Capability::Browse, async |store, instance| {
            browse::GuestIndices::new(p.pre())?
                .load(&mut *store, instance)?
                .call_categories(store, region)
                .await
        })
        .await
    }

    pub async fn browse_category(
        &self,
        p: &Plugin,
        id: &str,
        region: &str,
        cursor: Option<String>,
    ) -> Result<CategoryPage, CallError> {
        self.call(p, Capability::Browse, async |store, instance| {
            let guest = browse::GuestIndices::new(p.pre())?.load(&mut *store, instance)?;
            guest
                .call_fetch_category(store, id, region, cursor.as_deref())
                .await
        })
        .await
    }

    pub async fn browse_releases(
        &self,
        p: &Plugin,
        artist_id: &str,
        region: &str,
    ) -> Result<Vec<Release>, CallError> {
        self.call(p, Capability::Browse, async |store, instance| {
            browse::GuestIndices::new(p.pre())?
                .load(&mut *store, instance)?
                .call_releases(store, artist_id, region)
                .await
        })
        .await
    }

    /// Drops artwork outside the plugin's allowlist.
    fn keep_allowed(&self, p: &Plugin, images: &mut Vec<Image>) {
        images.retain(|i| self.check_url(p, &i.url).is_ok());
    }

    fn keep_allowed_tracks(&self, p: &Plugin, tracks: &mut [Track]) {
        tracks.iter_mut().for_each(|t| self.keep_allowed(p, &mut t.artwork));
    }
}

/// What a capability returns, checked against the plugin's allowlist.
pub(crate) trait Returned: Sized {
    fn checked(self, _host: &Host, _p: &Plugin) -> Result<Self, CallError> {
        Ok(self)
    }
}

impl Returned for Vec<String> {}
impl Returned for Option<EntityRef> {}
impl Returned for Lyrics {}

impl Returned for SearchResults {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        host.keep_allowed_tracks(p, &mut self.tracks);
        self.albums.iter_mut().for_each(|a| host.keep_allowed(p, &mut a.artwork));
        self.artists.iter_mut().for_each(|a| host.keep_allowed(p, &mut a.artwork));
        self.playlists.iter_mut().for_each(|pl| host.keep_allowed(p, &mut pl.artwork));
        Ok(self)
    }
}

impl Returned for EntityPage {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        host.keep_allowed(p, artwork(&mut self.entity));
        host.keep_allowed_tracks(p, &mut self.tracks);
        self.albums.iter_mut().for_each(|a| host.keep_allowed(p, &mut a.artwork));
        Ok(self)
    }
}

impl Returned for Vec<Category> {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        self.iter_mut()
            .for_each(|c| host.keep_allowed(p, &mut c.artwork));
        Ok(self)
    }
}

impl Returned for CategoryPage {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        let items = self.shelves.iter_mut().flat_map(|s| &mut s.items);
        items.for_each(|e| host.keep_allowed(p, artwork(e)));
        Ok(self)
    }
}

impl Returned for Vec<Release> {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        self.iter_mut()
            .for_each(|r| host.keep_allowed(p, &mut r.album.artwork));
        Ok(self)
    }
}

fn artwork(e: &mut Entity) -> &mut Vec<Image> {
    match e {
        Entity::Track(t) => &mut t.artwork,
        Entity::Album(a) => &mut a.artwork,
        Entity::Artist(a) => &mut a.artwork,
        Entity::Playlist(pl) => &mut pl.artwork,
    }
}

impl Returned for Vec<Track> {
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        host.keep_allowed_tracks(p, &mut self);
        Ok(self)
    }
}

impl Returned for Resolved {
    /// The stream URL must pass the allowlist; its headers lose framing/routing ones (`Host`
    /// would steer the core's download to another vhost on the same CDN).
    fn checked(mut self, host: &Host, p: &Plugin) -> Result<Self, CallError> {
        if host.check_url(p, &self.source.url).is_err() {
            return Err(CallError::Internal("stream url outside allowlist".into()));
        }
        crate::net::strip_routing_headers(&mut self.source.headers);
        Ok(self)
    }
}
