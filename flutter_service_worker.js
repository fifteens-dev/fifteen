'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"manifest.json": "4887e0b515bf7df25142d68e22ab219e",
"index.html": "021b420792c7dcb12d30d7ff9fc921aa",
"/": "021b420792c7dcb12d30d7ff9fc921aa",
"firebase-messaging-sw.js": "467a630554de84e8b2540b7569583344",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.bin.json": "61d2e3025db6a9cbfc6d06a995cfd80a",
"assets/assets/profile_images/sana.png": "fd81c95d6e3edecc1021b330670ba761",
"assets/assets/profile_images/mina.png": "326ef9e6cc4ce09e2c2629f00e050e46",
"assets/assets/profile_images/momo.png": "f0d4b2f27b6487d96150a191add12d39",
"assets/assets/icons/emotion.png": "5f6e4678969be8c2aee686147f575513",
"assets/assets/icons/lyrics/layout_3_selected.svg": "8cc901449b3cafc55266c480a0535d0b",
"assets/assets/icons/lyrics/layout_4_selected.svg": "50cac29ccab88603961d6611ef2dd522",
"assets/assets/icons/lyrics/layout_2_unselected.svg": "0e8ece4321782cbd826ceac5be021824",
"assets/assets/icons/lyrics/layout_4_unselected.svg": "2a0591e3a48a0d5f0d56499f97c378c1",
"assets/assets/icons/lyrics/layout_5_selected.svg": "e429f5cca08d71954b9f8ee18b666215",
"assets/assets/icons/lyrics/layout_1_unselected.svg": "29c34a50ee7f0e3f2c3e9942f8af6969",
"assets/assets/icons/lyrics/layout_3_unselected.svg": "ae7b8aae42b928c023d0081e21a1a6a1",
"assets/assets/icons/lyrics/layout_2_selected.svg": "a999fa94657e89df240527341098f38a",
"assets/assets/icons/lyrics/layout_1_selected.svg": "8ad5abc13a1f92c886e56353834aaf36",
"assets/assets/icons/lyrics/layout_5_unselected.svg": "e891acf1d1f5f0cfcc46d65af82463f3",
"assets/assets/icons/grid.svg": "43d13d4e5e42439105543aa1ef182a27",
"assets/assets/icons/message_circle.svg": "6e40f295db5640c5d12e09e665daccd1",
"assets/assets/icons/post_icon.svg": "090ac97917f73c24218e6b80cae4e1d7",
"assets/assets/icons/Spotify.png": "60870f926b57c7321833fdb51f4d1e60",
"assets/assets/icons/Vibe.png": "fc4d500753730bc54375584c9a0e411b",
"assets/assets/icons/Apple_Music.png": "d2fe6591eae16d6747fabbf85bb4f3ac",
"assets/assets/images/dummy_photo_10.jpg": "977e6ff662a7aec58563ccc84ae99ce6",
"assets/assets/images/dummy_photo_3.jpg": "7fff785ffebff3f0d5540d8cd62be330",
"assets/assets/images/dummy_photo_5.jpg": "b502d85cfc17287142edd39f10873875",
"assets/assets/images/dummy_photo_9.jpg": "7297bcdc2fcc227467c68bbef3953738",
"assets/assets/images/dummy_photo_4.jpg": "c96d4a7112e90423460fb9cd6efffce6",
"assets/assets/images/dummy_photo_11.jpg": "e7cc25bd51b55312e487ba85ee7c1698",
"assets/assets/images/dummy_photo_8.jpg": "8d489dc6104472909ddcf3740fb7be95",
"assets/assets/images/dummy_photo_1.jpg": "b1785ed7673d90cae155ddc83c2d6dec",
"assets/assets/images/dummy_photo_12.jpg": "a674136f3a62fa735a03a340e0610553",
"assets/assets/images/dummy_photo_2.jpg": "376cd7ac3b092555560e1aa68775c77b",
"assets/assets/images/dummy_photo_7.jpg": "e39efe0cf83a8af551996079e8888239",
"assets/assets/images/dummy_photo_6.jpg": "a2a172fe4e0a8304f4041b0fb45cbd71",
"assets/fonts/MaterialIcons-Regular.otf": "bbeaf94583f6c41b6593b01261be30ea",
"assets/NOTICES": "5450bee5e7958093f48cb2d9c78dc215",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin": "f119441514a756ca97ce6caf47252998",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter_bootstrap.js": "44fcc7088ade53a6766a880faaf88a65",
"version.json": "8c86ac827ebd5bca5cf02caaf5dd02dd",
"main.dart.js": "a4b0e5ee8985a0dd1577bb8515ed201c"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
