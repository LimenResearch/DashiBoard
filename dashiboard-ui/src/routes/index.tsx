import { Title } from '@solidjs/meta';
import { FilePicker } from '../components/FilePicker';
import logo from '../logo.svg';

export default function Home() {
  return (
    <main class="px-4 py-12">
      <Title>Home - Solid App</Title>
      <img
        src={logo}
        class="pointer-events-none mx-auto h-[24vmin] animate-[spin_20s_linear_infinite]"
        alt="Solid logo"
      />
      <h1 class="my-4 text-4xl font-bold">Hello Solid!</h1>
      <FilePicker></FilePicker>
    </main>
  );
}
