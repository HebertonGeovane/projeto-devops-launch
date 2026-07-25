const metadataUrl = "./metadata.json";

const elements = {
  containerStatus: document.querySelector("#containerStatus"),
  serverStatus: document.querySelector("#serverStatus"),
  portStatus: document.querySelector("#portStatus"),
  cloudStatus: document.querySelector("#cloudStatus"),
  deployDate: document.querySelector("#deployDate"),
  generalStatus: document.querySelector("#generalStatus"),

  modalContainer: document.querySelector("#modalContainer"),
  modalServer: document.querySelector("#modalServer"),
  modalPort: document.querySelector("#modalPort"),
  modalDeploy: document.querySelector("#modalDeploy"),
  modalCloud: document.querySelector("#modalCloud"),
  modalStatus: document.querySelector("#modalStatus"),
};

let projectStatus = null;

function setText(element, value) {
  element.textContent = value || "Não disponível";
}

function renderStatus(data) {
  const cloudDescription = [data.cloudProvider, data.region, data.instanceType]
    .filter(Boolean)
    .join(" • ");

  setText(
    elements.containerStatus,
    `${data.containerName} — ${data.containerStatus}`,
  );
  setText(elements.serverStatus, data.server);
  setText(elements.portStatus, data.port);
  setText(elements.cloudStatus, cloudDescription);
  setText(elements.deployDate, data.deployDate);
  setText(elements.generalStatus, data.applicationStatus);

  setText(
    elements.modalContainer,
    `${data.containerName} — ${data.containerStatus}`,
  );
  setText(elements.modalServer, data.server);
  setText(elements.modalPort, data.port);
  setText(elements.modalDeploy, data.deployDate);
  setText(elements.modalCloud, cloudDescription);
  setText(elements.modalStatus, data.applicationStatus);
}

function renderLoadError() {
  const message = "Metadados indisponíveis";

  Object.values(elements).forEach((element) => {
    setText(element, message);
  });
}

async function loadProjectMetadata() {
  const response = await fetch(`${metadataUrl}?timestamp=${Date.now()}`, {
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`Falha ao carregar metadata.json: ${response.status}`);
  }

  projectStatus = await response.json();
  renderStatus(projectStatus);
}

async function refreshStatus() {
  try {
    await loadProjectMetadata();
    return true;
  } catch (error) {
    console.error(error);
    renderLoadError();
    return false;
  }
}

const modal = document.querySelector("#statusModal");
const openStatusButton = document.querySelector("#openStatusButton");
const closeModalButton = document.querySelector("#closeModalButton");
const modalOkButton = document.querySelector("#modalOkButton");
const modalOverlay = document.querySelector("#modalOverlay");
const refreshStatusButton = document.querySelector("#refreshStatusButton");

async function openModal() {
  await refreshStatus();
  modal.classList.add("active");
  modal.setAttribute("aria-hidden", "false");
  document.body.classList.add("modal-open");
}

function closeModal() {
  modal.classList.remove("active");
  modal.setAttribute("aria-hidden", "true");
  document.body.classList.remove("modal-open");
}

openStatusButton.addEventListener("click", openModal);
closeModalButton.addEventListener("click", closeModal);
modalOkButton.addEventListener("click", closeModal);
modalOverlay.addEventListener("click", closeModal);

refreshStatusButton.addEventListener("click", async () => {
  refreshStatusButton.disabled = true;
  refreshStatusButton.textContent = "Consultando ambiente...";

  const success = await refreshStatus();

  refreshStatusButton.textContent = success
    ? "Informações atualizadas"
    : "Não foi possível atualizar";

  setTimeout(() => {
    refreshStatusButton.disabled = false;
    refreshStatusButton.textContent = "Atualizar informações";
  }, 1800);
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    closeModal();
  }
});

const menuButton = document.querySelector("#menuButton");
const menu = document.querySelector("#menu");
const menuLinks = document.querySelectorAll("#menu a");

menuButton.addEventListener("click", () => {
  const isOpen = menu.classList.toggle("active");
  menuButton.setAttribute("aria-expanded", String(isOpen));
});

menuLinks.forEach((link) => {
  link.addEventListener("click", () => {
    menu.classList.remove("active");
    menuButton.setAttribute("aria-expanded", "false");
  });
});

refreshStatus();
