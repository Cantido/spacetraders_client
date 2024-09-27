// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { CSS2DRenderer, CSS2DObject } from 'three/addons/renderers/CSS2DRenderer.js';

let Hooks = {};

// LiveView hook into localstorage

Hooks.SurveyStorage = {
  mounted() {
    if (!localStorage.getItem("surveys")) {
      localStorage.setItem("surveys", "[]");
    }

    const surveys = JSON.parse(localStorage.getItem("surveys"));

    surveys.forEach((survey) => {
      this.pushEvent("survey-loaded", survey, (reply, ref) => {});
    });

    this.handleEvent("survey-completed", (survey) => {
      console.log("got survey:");
      console.log(survey);

      let surveys = JSON.parse(localStorage.getItem("surveys"));
      surveys.push(survey);
      localStorage.setItem("surveys", JSON.stringify(surveys));
    });
  }
};

// ThreeJS hook into LiveView

Hooks.SystemMap = {
  system() { return JSON.parse(this.el.dataset.system) },
  mounted() {
    console.log("system map hook executing for system " + this.system().symbol);

    // Initialize threejs, set up camera, etc.

    const systemMap = document.getElementById("system-map");

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera( 75, systemMap.offsetWidth / systemMap.offsetHeight, 0.1, 1000 );

    const renderer = new THREE.WebGLRenderer();
    renderer.setSize( systemMap.offsetWidth, systemMap.offsetHeight );
    renderer.setAnimationLoop( animate );
    systemMap.appendChild( renderer.domElement );

    const labelRenderer = new CSS2DRenderer();
    labelRenderer.setSize(systemMap.offsetWidth, systemMap.offsetHeight);
    labelRenderer.domElement.style.position = "absolute";
    labelRenderer.domElement.style.top = "0px";
    systemMap.appendChild( labelRenderer.domElement );

    const controls = new OrbitControls( camera, labelRenderer.domElement );

    const raycaster = new THREE.Raycaster();
    raycaster.layers.disableAll();
    raycaster.layers.set(1);
    const pointer = new THREE.Vector2();


    // Draw map

    for(let i = 0; i < 500; i++) {
      const starGeometry = new THREE.SphereGeometry(0.1, 8, 8);
      const starMaterial = new THREE.MeshBasicMaterial( { color: 0x444444 });
      const starSphere = new THREE.Mesh(starGeometry, starMaterial);
      starSphere.position.x = Math.random() * 200 - 100;
      starSphere.position.y = Math.random() * 200 - 100;
      starSphere.position.z = Math.random() * 200 - 100;


      const starDistance = Math.sqrt(Math.pow(starSphere.position.x, 2) + Math.pow(starSphere.position.y, 2));

      if (starDistance > 25) {
        scene.add(starSphere);
      }
    }


    const sunGeometry = new THREE.SphereGeometry(0.1, 16, 16);
    const sunMaterial = new THREE.MeshBasicMaterial( { color: 0xffff00 });
    const sunSphere = new THREE.Mesh(sunGeometry, sunMaterial);
    scene.add(sunSphere);

    this.system().waypoints.forEach((waypoint) => {
      if (waypoint.type == "PLANET") {
        const planetGeometry = new THREE.SphereGeometry(0.05, 16, 16);
        const planetMaterial = new THREE.MeshBasicMaterial( { color: 0x4444ff });
        const planetSphere = new THREE.Mesh(planetGeometry, planetMaterial);
        planetSphere.position.x = waypoint.x / 50;
        planetSphere.position.z = waypoint.y / 50;
        planetSphere.layers.enable(1);
        planetSphere.name = waypoint.symbol;

        scene.add(planetSphere);

        const planetDiv = document.createElement("div");
        planetDiv.textContent = waypoint.symbol;
        planetDiv.className = "text-neutral-200";
        planetDiv.style.backgroundColor = "transparent";

        const planetLabel = new CSS2DObject(planetDiv);
        planetLabel.name = "label";
        planetLabel.position.set(0.1, 0, 0);
        planetLabel.center.set(0, 1);
        planetLabel.visible = false;
        planetSphere.add(planetLabel);

        const orbitalRadius = Math.sqrt(Math.pow(waypoint.x / 50, 2) + Math.pow(waypoint.y / 50, 2));

        const orbitCurve =
          new THREE.EllipseCurve(
            0, 0,
            orbitalRadius, orbitalRadius,
            0, 2 * Math.PI,
            false,
            0
          );

        const orbitPoints = orbitCurve.getPoints(200);
        const orbitGeometry = new THREE.BufferGeometry().setFromPoints(orbitPoints);
        const orbitMaterial = new THREE.LineBasicMaterial( { color: 0x666666 } );
        const orbitEllipse = new THREE.Line(orbitGeometry, orbitMaterial);
        orbitEllipse.rotateX(Math.PI / 2);
        scene.add(orbitEllipse);

      } else if (waypoint.type == "ASTEROID") {
        const asteroidGeometry = new THREE.SphereGeometry(0.05, 16, 16);
        const asteroidMaterial = new THREE.MeshBasicMaterial( { color: 0x999999 });
        const asteroidSphere = new THREE.Mesh(asteroidGeometry, asteroidMaterial);
        asteroidSphere.position.x = waypoint.x / 50;
        asteroidSphere.position.z = waypoint.y / 50;
        asteroidSphere.name = waypoint.symbol;
        asteroidSphere.layers.enable(1);

        scene.add(asteroidSphere);

        const asteroidDiv = document.createElement("div");
        asteroidDiv.textContent = waypoint.symbol;
        asteroidDiv.className = "text-neutral-200";
        asteroidDiv.style.backgroundColor = "transparent";

        const asteroidLabel = new CSS2DObject(asteroidDiv);
        asteroidLabel.name = "label";
        asteroidLabel.position.set(0.1, 0, 0);
        asteroidLabel.center.set(0, 1);
        asteroidLabel.visible = false;
        asteroidSphere.add(asteroidLabel);
      }

    });

    // initialize map state variables

    let highlightedWaypointName = null;
    let selectedWaypointName = null;


    // Hook into events

    function onPointerMove(event) {
      //pointer.x = (event.offsetX / systemMap.offsetWidth) * 2 - 1;
      //pointer.y = - (event.offsetY / systemMap.offsetHeight) * 2 + 1;
      pointer.x = (event.offsetX / systemMap.offsetWidth) * 2 - 1;
      pointer.y = - (event.offsetY / systemMap.offsetHeight) * 2 + 1;
    }

    window.addEventListener("pointermove", onPointerMove);



    this.el.addEventListener("click", (event) => {
      const intersects = raycaster.intersectObjects( scene.children );

      if (intersects.length > 0) {
        console.log("you did a click");


        selectedWaypointName = intersects[0].object.name;

        this.pushEvent("select-waypoint", {"waypoint-symbol": selectedWaypointName}, (reply, ref) => {});
      } else {
        selectedWaypointName = null;
      }
    });

    camera.position.z = 5;
    camera.position.y = 5;
    controls.update();


    function animate() {
      raycaster.setFromCamera(pointer, camera);

      const intersects = raycaster.intersectObjects( scene.children );

      if (intersects.length == 0 && typeof highlightedWaypointName === "string") {
        const wpObject = scene.getObjectByName(highlightedWaypointName);
        const label = wpObject.getObjectByName("label");
        label.visible = false;
        highlightedWaypointName = null;
      }

      for (let i = 0; i < intersects.length; i ++) {
        if (typeof highlightedWaypointName === "string") {
          const wpObject = scene.getObjectByName(highlightedWaypointName);
          const label = wpObject.getObjectByName("label");
          label.visible = false;
          highlightedWaypointName = null;
        }

        highlightedWaypointName = intersects[i].object.name;
      }

      if (typeof highlightedWaypointName === "string") {
        const wpObject = scene.getObjectByName(highlightedWaypointName);
        const label = wpObject.getObjectByName("label");
        label.visible = true;
      }


      // required if controls.enableDamping or controls.autoRotate are set to true
      controls.update();

      renderer.render( scene, camera );
      labelRenderer.render( scene, camera );

    }
  },
};


// LiveSocket setup

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket



