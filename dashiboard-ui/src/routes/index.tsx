import { Title } from '@solidjs/meta';
import { FilePicker } from '../components/FilePicker';
import logo from '../logo.svg';

export default function Home() {
  return (
    <main class="px-4 py-12">
      <Title>Load</Title>
      <FilePicker></FilePicker>
    </main>
  );
}
